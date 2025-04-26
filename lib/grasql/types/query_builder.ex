    case Selection.find_field(selection, name) do
      {:ok, field} ->
        add_field(query, selection, field)

      {:error, :not_found} ->
        handle_missing_field()
    end