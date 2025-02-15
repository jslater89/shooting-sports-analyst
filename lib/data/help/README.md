# The Help System

Analyst's help system provides in-app guidance on features and concepts.

## Help Topics
Help topics have a unique ID, a display name, and a content string. The content
string is formatted using a limited set of Markdown:
    * Headers: `# Header 1`, `## Header 2`, etc.
    * Ordered lists: `1. First item`, `2. Second item`, etc.
    * Unordered lists: `* First item`, `* Second item`, etc.
    * Links: `[Link text](https://example.com)`
        * Including links to other help topics: `[Link text](?topicId)`
    * Text decorations:
        * Bold: `**Bold text**`
        * Italics: `_Italic text_`
    * Line breaks with either two trailing spaces or a backslash (`\`)
        * In limited contexts only: in plain running text and in list items.
        * They probably don't work in the middle of other elements like links,
          emphasis, etc.