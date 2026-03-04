defmodule AgentPlatform.KnowledgeBase do
  @moduledoc """
  Builds and manages per-client knowledge bases.

  Responsibilities:
  - Scrape client websites and structure content
  - Store indexed documents to R2
  - Retrieve relevant context for agent responses
  - Maintain industry-specific default knowledge
  """

  require Logger

  alias AgentPlatform.Storage

  @max_scrape_pages 20
  @max_content_length 50_000
  @chunk_size 2000

  def build_from_website(client) do
    case client.website do
      nil ->
        {:error, "No website URL provided"}

      url ->
        Logger.info("Scraping website for knowledge base: #{url}")

        with {:ok, content} <- scrape_website(url),
             {:ok, structured} <- structure_content(content, client),
             :ok <- store_knowledge(client, structured) do
          {:ok, structured}
        end
    end
  end

  def store(key, knowledge) do
    content =
      case knowledge do
        %{} = map -> Jason.encode!(map)
        binary when is_binary(binary) -> binary
        list when is_list(list) -> Jason.encode!(list)
      end

    Storage.put(key, content, content_type: "application/json")
  end

  def retrieve(key, query) do
    case Storage.get(key) do
      {:ok, content} ->
        knowledge =
          case Jason.decode(content) do
            {:ok, parsed} -> parsed
            _ -> content
          end

        relevant = find_relevant_chunks(knowledge, query)
        {:ok, relevant}

      {:error, reason} ->
        Logger.warn("Knowledge base retrieval failed for #{key}: #{inspect(reason)}")
        {:ok, ""}
    end
  end

  def industry_defaults(industry) do
    %{
      industry: to_string(industry),
      content: industry_default_content(industry),
      source: "industry_defaults",
      chunks: chunk_content(industry_default_content(industry))
    }
  end

  # --- Website Scraping ---

  defp scrape_website(url) do
    normalized_url =
      if String.starts_with?(url, "http") do
        url
      else
        "https://#{url}"
      end

    case Req.get(normalized_url, receive_timeout: 30_000, follow_redirects: true) do
      {:ok, %{status: 200, body: body}} ->
        text = extract_text_from_html(body)

        if String.length(text) > 100 do
          {:ok, String.slice(text, 0, @max_content_length)}
        else
          {:error, "Insufficient content scraped from #{url}"}
        end

      {:ok, %{status: status}} ->
        {:error, "Website returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "Failed to scrape #{url}: #{inspect(reason)}"}
    end
  end

  defp extract_text_from_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/s, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/s, "")
    |> String.replace(~r/<nav[^>]*>.*?<\/nav>/s, "")
    |> String.replace(~r/<footer[^>]*>.*?<\/footer>/s, "")
    |> String.replace(~r/<header[^>]*>.*?<\/header>/s, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&[a-zA-Z]+;/, " ")
    |> String.replace(~r/&#\d+;/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_text_from_html(_), do: ""

  # --- Content Structuring ---

  defp structure_content(raw_content, client) do
    chunks = chunk_content(raw_content)

    structured = %{
      client_id: client.id,
      business_name: client.business_name,
      industry: to_string(client.industry),
      source: client.website,
      scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      content: raw_content,
      chunks: chunks,
      chunk_count: length(chunks)
    }

    {:ok, structured}
  end

  defp chunk_content(content) when is_binary(content) do
    content
    |> String.split(~r/\n{2,}|\. /, trim: true)
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join(&1, " "))
    |> Enum.filter(fn chunk -> String.length(chunk) > 50 end)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      %{
        id: idx,
        content: String.slice(chunk, 0, @chunk_size),
        length: String.length(chunk)
      }
    end)
  end

  defp chunk_content(_), do: []

  # --- Knowledge Storage ---

  defp store_knowledge(client, structured) do
    key = "clients/#{client.id}/knowledge/base"
    store(key, structured)
  end

  # --- Retrieval ---

  defp find_relevant_chunks(knowledge, query) when is_map(knowledge) do
    chunks = knowledge["chunks"] || []
    query_words = tokenize(query)

    ranked =
      chunks
      |> Enum.map(fn chunk ->
        chunk_words = tokenize(chunk["content"] || "")
        score = jaccard_similarity(query_words, chunk_words)
        {chunk, score}
      end)
      |> Enum.sort_by(fn {_chunk, score} -> score end, :desc)
      |> Enum.take(3)
      |> Enum.map(fn {chunk, _score} -> chunk["content"] || "" end)

    Enum.join(ranked, "\n\n")
  end

  defp find_relevant_chunks(content, _query) when is_binary(content) do
    String.slice(content, 0, 3000)
  end

  defp find_relevant_chunks(_, _), do: ""

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp jaccard_similarity(set_a, set_b) do
    intersection = MapSet.intersection(set_a, set_b) |> MapSet.size()
    union = MapSet.union(set_a, set_b) |> MapSet.size()

    if union > 0, do: intersection / union, else: 0.0
  end

  # --- Industry Defaults ---

  defp industry_default_content(:real_estate) do
    """
    Real estate agency providing residential and commercial property services.
    Services include property listings, buyer representation, seller representation,
    property management, market analysis, and home valuation.
    We help clients buy, sell, rent, and manage properties.
    Our agents are experienced in the local market and provide personalized service.
    We offer virtual tours, open houses, and private showings.
    Financing guidance and mortgage referrals available.
    """
  end

  defp industry_default_content(:medical) do
    """
    Medical practice providing healthcare services to patients.
    Services include routine checkups, preventive care, specialist consultations,
    lab work, vaccinations, and chronic disease management.
    We accept most major insurance plans.
    New patients welcome. Same-day appointments available for urgent needs.
    Telehealth appointments available for eligible conditions.
    Patient portal available for scheduling, results, and messaging.
    """
  end

  defp industry_default_content(:legal) do
    """
    Law firm providing legal services across multiple practice areas.
    Services include consultations, legal representation, document preparation,
    contract review, and dispute resolution.
    Practice areas may include family law, business law, estate planning,
    real estate transactions, and personal injury.
    Initial consultations available. Flexible fee arrangements.
    Confidential and professional legal counsel.
    """
  end

  defp industry_default_content(:restaurant) do
    """
    Restaurant providing dining experiences for guests.
    Services include dine-in, takeout, catering, and private events.
    We accommodate dietary restrictions and allergies.
    Reservations recommended for parties of 6 or more.
    Gift cards available. Loyalty program for regular guests.
    Special menus for holidays and seasonal events.
    """
  end

  defp industry_default_content(_) do
    """
    Business providing professional services to customers.
    We are committed to quality service and customer satisfaction.
    Contact us for more information about our offerings.
    Business hours and service details available upon request.
    """
  end
end
