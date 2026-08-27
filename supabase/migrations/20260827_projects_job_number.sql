-- Job Number: shown alongside Project Name on the projects list and searchable together with it.
ALTER TABLE projects ADD COLUMN IF NOT EXISTS job_number text;
