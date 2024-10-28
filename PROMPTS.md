
# LLM Prompts

## LLM Prompts for generating bake files

From a blog or tutoria:

```
Can you convert the provided instructions below into a markdown file of the following style for me? Put everything which I need to manually perform/execute as list items with a checkbox ' - [ ]'. Things which could be executed on the shell can be given by escaping in single backticks and ruby code can be provided by triple backticks. In the Ruby code you can access all common Thor actions (e.g. `copy_file`, `gsub_file`, etc.) as common in Rails Application Templates.

To distinguish manual instructions from executable code, for executable code you must separate the human readable part by colon from the code part starting with a single or triple backtick (depending on shell vs ruby). For example:

- [ ] ...instruction for humans which require manual...
- [ ] short description of shell code which follows: `echo "Hello World"`
  or if shell command is easy or self-explanatory:
  - [ ] `echo "Self explanatory shell code can be inline"`
- [ ] short description of ruby code which follows: ```puts "Hello World"```
  or if ruby code is self-explanatory: 
  - [ ] ```puts "Self explanatory Ruby code can be inline"```

Important: Fenced code blocks starting with '```ruby' are executed with ruby, so you can't use them as part of manual tasks to provide example content to the user. Rather, ideally use gsub_file or similar to perform the update by scripting or use '```rb' to denote non-executable Ruby code.

Keep the generated markdown lean and clean and tight. Bold highlights should be used sparingly. If necessary use headings to separate. 

To give you an idea, I am providing you with a comprehensive example of a such a markdown file (bake file) that you can use as a template.

% YOUR EXAMPLE %

Now please convert the instructions per our previous conversation in this format.
```

## LLM Prompt to review bake files

```
The following is a markdown file that contains both manual tasks for users as well as executable sections of bash/shell scripts (denoted by single backticks) and ruby code (denoted by triple backticks). Consider the use of the inline syntax for both bash and ruby code in the markdown file correct and don't convert it into multiline fenced code blocks unless readability would greatly improve.

In the Ruby code you can access all common Thor actions (e.g. `copy_file`, `gsub_file`, etc.) as common in Rails Application Templates. If the template file could be much improved by extract commonly used functionality into a Thor action, please point it out in your reply.

Do NOT convert bash commands to Ruby or Ruby commands to bash unless there is a clear need or major improvement in readability in either direction.

Please review the file carefully and return it including any improvements you have made. Try to keep the tone and terseness of the file. In your reply explain any larger bug-fixes you had to perform.


```
