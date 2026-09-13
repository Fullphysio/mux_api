// Captures test/fixtures/pagination_golden.json: the sequence of requests
// @mux/ts issues while auto-paginating each page shape, and where it stops.
// `page` names the shape upstream uses for the endpoint (its api.md return
// type) — it is not inferable from the response and is pinned per operation.

'use strict';

const { loadMux, recordingFetch, clientWith, writeFixture } = require('./common');

const Mux = loadMux();

async function capture(name, page, input, responses, invoke) {
  const { fetch, calls } = recordingFetch(responses);
  const client = clientWith(Mux, fetch);
  const first = await invoke(client);
  const firstPage = {
    hasNextPage: first.hasNextPage(),
    dataIds: first.data.map((item) => item.id),
    nextCursor: first.next_cursor === undefined ? null : first.next_cursor,
    totalRowCount: first.total_row_count === undefined ? null : first.total_row_count,
    timeframe: first.timeframe === undefined ? null : first.timeframe,
    pageNumber: first.page === undefined ? null : first.page,
    limit: first.limit === undefined ? null : first.limit,
  };
  const items = [];
  for await (const item of first) items.push(item.id);
  return {
    name,
    page,
    input,
    responses: responses.map((r) => r.body),
    firstPage,
    autoPagedIds: items,
    requests: calls.map((c) => c.url),
  };
}

const ok = (body) => ({ status: 200, body });

async function main() {
  const cases = [];

  cases.push(
    await capture(
      'base_page_uploads_stops_on_empty_page',
      'base',
      { path: '/video/v1/uploads', query: { limit: 2 } },
      [ok({ data: [{ id: 'u1' }, { id: 'u2' }] }), ok({ data: [{ id: 'u3' }] }), ok({ data: [] })],
      (c) => c.video.uploads.list({ limit: 2 }),
    ),
  );

  cases.push(
    await capture(
      'base_page_explicit_page_param',
      'base',
      { path: '/video/v1/uploads', query: { page: 3, limit: 1 } },
      [ok({ data: [{ id: 'u5' }] }), ok({ data: [] })],
      (c) => c.video.uploads.list({ page: 3, limit: 1 }),
    ),
  );

  cases.push(
    await capture('base_page_empty_first_page', 'base', { path: '/video/v1/uploads', query: {} }, [ok({ data: [] })], (c) => c.video.uploads.list()),
  );

  cases.push(
    await capture(
      'cursor_page_assets',
      'cursor',
      { path: '/video/v1/assets', query: { limit: 2 } },
      [ok({ data: [{ id: 'a1' }, { id: 'a2' }], next_cursor: 'cursor-2' }), ok({ data: [{ id: 'a3' }], next_cursor: '' })],
      (c) => c.video.assets.list({ limit: 2 }),
    ),
  );

  cases.push(
    await capture(
      'cursor_page_missing_next_cursor',
      'cursor',
      { path: '/video/v1/assets', query: {} },
      [ok({ data: [{ id: 'a1' }] })],
      (c) => c.video.assets.list(),
    ),
  );

  cases.push(
    await capture(
      'timeframe_page_delivery_usage_uses_server_page_number',
      'withTimeframe',
      { path: '/video/v1/delivery-usage', query: { timeframe: ['1', '2'] } },
      [
        ok({ data: [{ id: 'd1' }], timeframe: [1, 2], page: 1, limit: 100 }),
        ok({ data: [{ id: 'd2' }], timeframe: [1, 2], page: 2, limit: 100 }),
        ok({ data: [], timeframe: [1, 2], page: 3, limit: 100 }),
      ],
      (c) => c.video.deliveryUsage.list({ timeframe: ['1', '2'] }),
    ),
  );

  cases.push(
    await capture(
      'base_page_incidents_ignores_total_row_count',
      'base',
      { path: '/data/v1/incidents', query: { limit: 1 } },
      [ok({ data: [{ id: 'i1' }], total_row_count: 1, timeframe: [1, 2] }), ok({ data: [], total_row_count: 1, timeframe: [1, 2] })],
      (c) => c.data.incidents.list({ limit: 1 }),
    ),
  );

  writeFixture('pagination_golden', {
    seam: 'list() through the `fetch` client option, then `for await` over the page',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
