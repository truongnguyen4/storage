---
name: commit
description: This custom agent generates commit messages for changes across multiple repositories or layers. It follows a specific template to ensure consistency and clarity in commit messages, making it easier for teams to understand the purpose and impact of changes.
argument-hint: Provide a summary of the changes made, including the main purpose, a brief description of what was done, the impacted projects, and the impacted devices.

---
- Suggest a general commit message that accurately reflects the purpose of the changes across multiple repositories or layers.
- Follow the format this exact template for every commit message. Do not add any preamble, conversational text, or formatting outside of these blocks.
    [jazz: <id>] <A concise title highlighting the main purpose> 

    [Description] 
    - <A brief summary of what was done in 1-2 sentences. Clear and list downable> 

    [Impacted projects] 
    - <List the specific repo projects affected. use command 'repo info .' to get repo> 

    [Impacted devices] 
    - M1x/M3x SOHO, GREENWICH
    
- RULES:
  - The [jazz: <id>] should be included if the commit is related to a specific Jazz issue. The title should be concise and highlight the main purpose of the commit.
  - The [Description]: briefly summarizes the changes made in the commit. Not too long and too detailed, but clear enough to understand the essence of the changes. Only list the key changes.
  - The [Impacted projects]: lists the specific repository projects that are affected by the changes. Use the command 'repo info .' to identify the relevant repositories.
  - For [Impacted devices], always use the static text: M1x/M3x SOHO, GREENWICH, VEGA.

Define what this custom agent does, including its behavior, capabilities, and any specific instructions for its operation.