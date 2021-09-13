/*
 *
 * Elasticsearch Helpers
 *
 */

export async function getIndicesDirectory (esUrl) {
  /* Return an array of _source properties from each document in the indices
     directory, or an empty array if something goes wrong.
  */
  const res = await (await fetch(`${esUrl}/directory_/_search`))
  if (res.status === 200) {
    const data = await res.json()
    return data.hits.hits.map(x => x._source)
  }
  console.error("Unable to retrieve the indices directory from the Elasticsearch server")
  return []
}

export function buildQuery (
  indices, {
    q = "",
    filters = {},
    start = 0,
    size = 20,
    fields = [ "*" ],
    aggregationNameFieldMap = {},
    _source = "*"
  }
) {
  /* Return an Elasticsearch query object for the given parameters. */

  // Init the query context to a match_all.
  let queryContext = { match_all: {} }

  // If a query string was specified, add a full text query.
  if (q.length > 0) {
    queryContext = {
      simple_query_string: {
        query: q,
        default_operator: "and",
        fields,
      }
    }
  }

  // If filters were specified, build the filter context.
  const filterContext = []
  Array.from(filters.entries()).forEach(([ name, values ]) => {
    (Array.isArray(values) ? values : [ values ]).forEach(value => {
      filterContext.push({
        term: { [name]: value }
      })
    })
  })

  // Define the base query object.
  const query = {
    from: start,
    size,
    query: {},
  }

  if (filterContext.length === 0) {
    // Build non-filtered query.
    query.query = queryContext
  } else {
    // Build filtered query.
    query.query = {
      bool: {
        must: queryContext,
        filter: filterContext,
      },
    }
  }

  // Add any aggregations.
  query.aggs = {}
  Array.from(aggregationNameFieldMap.entries())
    .forEach(([ name, field ]) => {
      query.aggs[name] = {
        terms: {
          field,
          // Size defines the maximum number of buckets to return.
          // TODO - maybe parameterize this
          size: 25,
        },
      }
    })

  // Specify which document fields we want returned.
  query._source = _source

  return query
}

export async function executeQuery (esUrl, indices, query) {
  /* Perform the search and return the response, or return null if something
     goes wrong (e.g. server not reachable, response not JSON, etc.)
  */
  let fetchResponse
  try {
    fetchResponse = await fetch(`${esUrl}/${indices.join(",")}/_search`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(query)
    })
  } catch (e) {
    return null
  }

  let data
  // If the content is not JSON, abort, otherwise attempt to decode it.
  if (!fetchResponse.headers.get("Content-Type").startsWith("application/json")) {
    return null
  }
  try {
    data = await fetchResponse.json()
  } catch (e) {
    return null
  }

  if (!fetchResponse.ok) {
    // If it looks like an ES error, print the 'reason' to the console.
    if (data.error && data.error.reason) {
      console.error(`Search error: ${data.error.reason}`)
    }
    return null
  }

  return data
}
