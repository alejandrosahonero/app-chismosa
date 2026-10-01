-- Loads public.common_words (0016) from supabase/seed/common_words.txt on
-- GitHub, so the 80,000 words never have to be pasted into the SQL Editor.
-- pg_net is asynchronous: run step 1, wait a few seconds, then run step 2.
-- Regenerate the file with tool/build_common_words.py.

-- Step 1: request the file. Note the id it returns.
select net.http_get(
  'https://raw.githubusercontent.com/alejandrosahonero/app-chismosa/develop/supabase/seed/common_words.txt'
) as request_id;

-- Step 2: load it (replace <id> with the request id from step 1).
-- insert into public.common_words (word)
-- select w
-- from net._http_response r, regexp_split_to_table(r.content, '\n') as w
-- where r.id = <id> and r.status_code = 200 and w ~ '^[a-z]+$'
-- on conflict do nothing;
