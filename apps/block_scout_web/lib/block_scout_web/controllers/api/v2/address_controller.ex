defmodule BlockScoutWeb.API.V2.AddressController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 3,
      paging_options: 1,
      split_list_by_page: 1,
      current_filter: 1
    ]

  import BlockScoutWeb.PagingHelper,
    only: [delete_parameters_from_next_page_params: 1, token_transfers_types_options: 1]

  alias BlockScoutWeb.API.V2.{AddressView, BlockView, TransactionView}
  alias Explorer.{Chain, Market}
  alias Indexer.Fetcher.TokenBalanceOnDemand

  @transaction_necessity_by_association [
    necessity_by_association: %{
      [created_contract_address: :names] => :optional,
      [from_address: :names] => :optional,
      [to_address: :names] => :optional,
      :block => :optional,
      [created_contract_address: :smart_contract] => :optional,
      [from_address: :smart_contract] => :optional,
      [to_address: :smart_contract] => :optional
    }
  ]

  @token_transfer_necessity_by_association [
    necessity_by_association: %{
      :to_address => :optional,
      :from_address => :optional,
      :block => :optional
    }
  ]

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  def address(conn, %{"address_hash" => address_hash_string}) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)},
         {:not_found, {:ok, address}} <- {:not_found, Chain.hash_to_address(address_hash)} do
      conn
      |> put_status(200)
      |> render(:address, %{address: address})
    end
  end

  def counters(conn, %{"address_hash" => address_hash_string}) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)},
         {:not_found, {:ok, address}} <- {:not_found, Chain.hash_to_address(address_hash)} do
      {validation_count} = Chain.address_counters(address)

      transactions_from_db = address.transactions_count || 0
      token_transfers_from_db = address.token_transfers_count || 0
      address_gas_usage_from_db = address.gas_used || 0

      json(conn, %{
        transaction_count: to_string(transactions_from_db),
        token_transfer_count: to_string(token_transfers_from_db),
        gas_usage_count: to_string(address_gas_usage_from_db),
        validation_count: to_string(validation_count)
      })
    end
  end

  def token_balances(conn, %{"address_hash" => address_hash_string}) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      token_balances =
        address_hash
        |> Chain.fetch_last_token_balances()

      Task.start_link(fn ->
        TokenBalanceOnDemand.trigger_fetch(address_hash, token_balances)
      end)

      token_balances_with_price =
        token_balances
        |> Market.add_price()

      conn
      |> put_status(200)
      |> render(:token_balances, %{token_balances: token_balances_with_price})
    end
  end

  def transactions(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      options =
        @transaction_necessity_by_association
        |> Keyword.merge(paging_options(params))
        |> Keyword.merge(current_filter(params))

      results_plus_one = Chain.address_to_transactions_with_rewards(address_hash, options)
      {transactions, next_page} = split_list_by_page(results_plus_one)

      next_page_params =
        next_page |> next_page_params(transactions, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:transactions, %{transactions: transactions, next_page_params: next_page_params})
    end
  end

  def token_transfers(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      options =
        @token_transfer_necessity_by_association
        |> Keyword.merge(paging_options(params))
        |> Keyword.merge(current_filter(params))
        |> Keyword.merge(token_transfers_types_options(params))

      results_plus_one =
        Chain.address_hash_to_token_transfers_new(
          address_hash,
          options
        )

      {transactions, next_page} = split_list_by_page(results_plus_one)

      next_page_params =
        next_page |> next_page_params(transactions, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:token_transfers, %{token_transfers: transactions, next_page_params: next_page_params})
    end
  end

  def internal_transactions(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      full_options =
        [
          necessity_by_association: %{
            [created_contract_address: :names] => :optional,
            [from_address: :names] => :optional,
            [to_address: :names] => :optional,
            [created_contract_address: :smart_contract] => :optional,
            [from_address: :smart_contract] => :optional,
            [to_address: :smart_contract] => :optional
          }
        ]
        |> Keyword.merge(paging_options(params))
        |> Keyword.merge(current_filter(params))

      results_plus_one = Chain.address_to_internal_transactions(address_hash, full_options)
      {internal_transactions, next_page} = split_list_by_page(results_plus_one)

      next_page_params =
        next_page |> next_page_params(internal_transactions, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:internal_transactions, %{
        internal_transactions: internal_transactions,
        next_page_params: next_page_params
      })
    end
  end

  def logs(conn, %{"address_hash" => address_hash_string, "topic" => topic} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      prepared_topic = String.trim(topic)

      formatted_topic = if String.starts_with?(prepared_topic, "0x"), do: prepared_topic, else: "0x" <> prepared_topic

      results_plus_one = Chain.address_to_logs(address_hash, topic: formatted_topic)

      {logs, next_page} = split_list_by_page(results_plus_one)

      next_page_params = next_page |> next_page_params(logs, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:logs, %{logs: logs, next_page_params: next_page_params})
    end
  end

  def logs(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      results_plus_one = Chain.address_to_logs(address_hash, paging_options(params))
      {logs, next_page} = split_list_by_page(results_plus_one)

      next_page_params = next_page |> next_page_params(logs, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:logs, %{logs: logs, next_page_params: next_page_params})
    end
  end

  def blocks_validated(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      full_options =
        Keyword.merge(
          [
            necessity_by_association: %{
              miner: :required,
              nephews: :optional,
              transactions: :optional,
              rewards: :optional
            }
          ],
          paging_options(params)
        )

      results_plus_one = Chain.get_blocks_validated_by_address(full_options, address_hash)
      {blocks, next_page} = split_list_by_page(results_plus_one)

      next_page_params = next_page |> next_page_params(blocks, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(BlockView)
      |> render(:blocks, %{blocks: blocks, next_page_params: next_page_params})
    end
  end

  def coin_balance_history(conn, %{"address_hash" => address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)},
         {:not_found, {:ok, _address}, _} <-
           {:not_found, Chain.hash_to_address(address_hash), :empty_items_with_next_page_params} do
      full_options = paging_options(params)

      results_plus_one = Chain.address_to_coin_balances(address_hash, full_options)

      {coin_balances, next_page} = split_list_by_page(results_plus_one)

      next_page_params =
        next_page |> next_page_params(coin_balances, params) |> delete_parameters_from_next_page_params()

      conn
      |> put_status(200)
      |> put_view(AddressView)
      |> render(:coin_balances, %{coin_balances: coin_balances, next_page_params: next_page_params})
    end
  end

  def coin_balance_history_by_day(conn, %{"address_hash" => address_hash_string}) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)} do
      balances_by_day =
        address_hash
        |> Chain.address_to_balances_by_day(true)

      conn
      |> put_status(200)
      |> put_view(AddressView)
      |> render(:coin_balances_by_day, %{coin_balances_by_day: balances_by_day})
    end
  end
end
