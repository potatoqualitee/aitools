Review /Tests/pdf/immunization.pdf carefully for data quality issues.

I've already imported the data exactly as shown in the PDF into tempdb tables
(look it up on localhost using windows credentials).

Now I need you to:

1. ANALYZE the document for inconsistencies, errors, or suspicious data:
   - Does the breed match the typical characteristics shown?
   - Are weights reasonable for the listed breed?
   - Any conflicting information between fields?
   - Dates that don't make sense?
   - Any other red flags?

2. Generate T-SQL UPDATE statements to correct any issues you find

3. List ALL data inconsistencies you discovered