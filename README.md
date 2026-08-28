# SMI Files

Work-order management for an industrial maintenance team — built **offline-first**, because the technician is inside a factory with no signal when the work actually happens.

Flutter · Supabase · Android, iOS, Windows, macOS, Linux, web

Built by [Kaiki Quadros Ferreira](https://github.com/dev-kaiki) at SMI, published with the company's permission.

---

## Why offline-first is the whole design

A maintenance technician opens a machine in the middle of a plant floor. Concrete walls, steel everywhere, no mobile signal — and even when there is signal, it drops halfway through uploading a 4 MB photo of a burnt board.

If the app assumes the network works, the technician loses the record and has to redo it from memory later. So the app never assumes it:

- **Everything is written locally first.** Photos and videos are copied into a persistent outbox directory in app storage the moment they are taken.
- **An outbox queues the uploads** with explicit states — `pending`, `uploading`, `uploaded`, `missing`, `failed` — so nothing is silently lost between them.
- **Retries are automatic**, tracking attempt count and last-attempt time per item, and a `missing` state covers the case where the local file itself vanished.
- **The technician can see the queue** and what is still waiting, instead of guessing whether the work was saved.

The rule behind it: *if the upload fails or the app is killed, a persistent copy exists on disk, so the user does not lose the media.*

## What it does

| | |
|---|---|
| **Work orders** | Create and browse orders, with parent/sub-order relationships and shop-area tagging |
| **Media per order** | Photos and videos attached to the order that produced them, with watermarking |
| **Time entries** | Hours logged per technician per day, with normal / 50% / 100% overtime bands |
| **Field checklists** | Configurable checklist templates filled in on site |
| **PDF export** | The order and its record exported as a report |
| **Backup** | Local export of order data |

## Layout

```
lib/
  core/supabase/     client setup — credentials come from --dart-define, never the source
  features/
    auth/            login
    os/              work orders: list, create, media, time entries, repositories
    checklist/       templates and per-order checklists
    explore/         search across orders
  services/          outbox: queue, uploader, and its UI
  pending/           pending media: store, retry service, indicator
  utils/             PDF export, watermarking, worktime rules, routing
  widgets/           shared UI components
```

The split between `services/outbox` and `pending/` is deliberate: the outbox owns the
durable queue and its lifecycle, while `pending/` owns the retry policy and how the
backlog is surfaced to the user.

## Running it

Requires a Supabase project. Credentials are **not** in the source — pass them at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

The app refuses to start without both, rather than falling back to a default.

## Notes on this repository

This is a **sanitized publication** of a system in internal testing at SMI. The Supabase
credentials that were compiled into the client have been removed, and no customer data,
work orders or media are included — the repository is code only.

## License

MIT — see [LICENSE](LICENSE). Published with permission from SMI.
