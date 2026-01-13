--- Pattern translation: ripgrep regex => Vim "very magic" regex.
---
--- While best-effort, it covers a wide range of practical use cases.
---
--- It does not cover:
---
---   * ripgrep features that require PCRE2 (e.g. backreferences), because we
---     disallow PCRE2
---   * ripgrep features not supported by vimgrep
---   * vimgrep syntax with no ripgrep equivalent
---   * lookarounds (high complexity, limited utility in code search)
---
--- When translation is not possible, the search still works; only highlighting and
--- n/N navigation are unavailable.
---
---@module 'brook.pattern'
local M = {}

local types = require 'brook.types'

local word_atoms = {
  ['\\w'] = true,
  ['\\d'] = true,
}

local non_word_atoms = {
  ['\\s'] = true,
  ['\\t'] = true,
  ['\\n'] = true,
  ['\\r'] = true,
  ['\\W'] = true,
}

-- Atoms that could match either word or non-word characters.
-- \S matches any non-whitespace: could be 'a' (word) or '!' (non-word)
-- \D matches any non-digit: could be 'a' (word) or '!' (non-word)
local unknown_atoms = {
  ['\\S'] = true,
  ['\\D'] = true,
}

local non_word_atoms_before = {
  ['|'] = true, -- alternation
  ['('] = true, -- group start
  ['^'] = true, -- start-of-line anchor
}

local non_word_atoms_after = {
  ['|'] = true, -- alternation
  [')'] = true, -- group end
  ['$'] = true, -- end-of-line anchor
}

---@enum wordness
M._wordness = {
  word = 'word',
  non_word = 'non-word',
  unknown = 'unknown',
}

--- Result of pattern translation.
---
---@class brook.PatternResult
---@field pattern string|nil The translated Vim regex (nil when unsupported)
---@field warning string|nil Warning message for adjustments or failures

--- Translates a ripgrep pattern to Vim regex syntax.
---
--- Targets very magic mode (\v) for closer semantic alignment with ripgrep's
--- Rust regex syntax.
---
--- Supported:
---   - literal characters and basic metacharacters
---   - character classes and shorthands (\d, \w, etc.)
---   - word boundaries (\b)
---   - quantifiers (greedy and non-greedy)
---   - numbered groups (capturing and non-capturing)
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.PatternOpts Options affecting pattern translation
---
---@return brook.PatternResult result The translation result with pattern and optional warning
function M.rg_to_vim(pattern, opts)
  opts = opts or {}

  -- Case 1. Literal search (verbatim, no regex, no translation)
  --------------------------------------------------------------
  -- For literal (fixed-string) searches, use very-nomagic mode (\V).
  -- Only backslash and the search delimiter (/) need escaping.
  if opts.fixed then
    pattern = pattern:gsub('\\', '\\\\'):gsub('/', '\\/')
    if opts.word then
      pattern = '\\<' .. pattern .. '\\>'
    end

    local prefix = '\\V'
    -- Case-sensitivity must be set at the beginning of the pattern, or it will be
    -- interpreted as an escaped character.
    if opts.case == types.search_case.sensitive then
      prefix = '\\C' .. prefix
    elseif opts.case == types.search_case.insensitive then
      prefix = '\\c' .. prefix
    end

    return { pattern = prefix .. pattern, warning = nil }
  end

  -- Case 2. Normal search pattern: translate rg to vim
  -----------------------------------------------------
  local result = {}
  local warnings = {}
  local len = #pattern
  local in_char_class = false
  ---@type wordness|nil
  local wordness_before = M._wordness.non_word
  local pending_class_wordness = nil -- wordness to assign when exiting current class
  local was_quantifier = false       -- needed later for wordness detection
  local i = 1

  while i <= len do
    was_quantifier = false -- reset each iteration

    local char = pattern:sub(i, i)
    local next_char = pattern:sub(i + 1, i + 1)
    local atom = pattern:sub(i, i + 1)

    if char == '\\' and next_char ~= '' then
      -- Escaped character: handle as a unit

      if in_char_class then
        -- Inside character class: pass through unchanged
        table.insert(result, '\\')
        table.insert(result, next_char)
      elseif next_char == 'b' then
        -- Translate ripgrep word boundary to vimgrep word boundary.
        --
        -- The end goal is to do our best to avoid confusing the user with that
        -- construct, `%(<|>)` in the notification line. That is a technically
        -- mostly-valid translation of `\b`, but it sure looks alien at first
        -- glance.
        --
        -- This is one place where ripgrep and vimgrep diverge the most.
        -- ripgrep has no notion of start or end of word for boundaries, so we
        -- need to infer "wordness" from the context. Even then, only an
        -- approximate translation is possible because ripgrep's word boundaries
        -- are unicode-aware, whereas in Vim it depends on the value of
        -- `iskeyword`. Even ignoring those incompatibilities, this is already
        -- a considerable undertaking for what is arguably a cosmetic concern.
        -- Determining wordness of character even required branching into a
        -- completely separately function.
        local char_after = pattern:sub(i + 2, i + 2)
        local atom_after = pattern:sub(i + 2, i + 3)

        local wordness_after = M._wordness.unknown
        if char_after == '.' then
          wordness_after = M._wordness.unknown
        elseif char_after == '[' then
          -- Character class follows: determine its wordness
          wordness_after = M._classify_char_class_wordness(pattern:sub(i + 2)) or M._wordness.unknown
        elseif unknown_atoms[atom_after] then
          wordness_after = M._wordness.unknown
        elseif word_atoms[atom_after] or char_after:match('[%w]') then
          wordness_after = M._wordness.word
        elseif non_word_atoms[atom_after] or non_word_atoms_after[atom_after]
            or char_after:match('[^%w]') or char_after == '' then
          wordness_after = M._wordness.non_word
        end

        if wordness_before == M._wordness.non_word and wordness_after == M._wordness.word then
          -- NON-WORD \b WORD => start of word
          table.insert(result, '<')
        elseif wordness_before == M._wordness.word and wordness_after == M._wordness.non_word then
          -- WORD \b NON-WORD => end of word
          table.insert(result, '>')
        else
          -- Generic word boundary: \b -> %(<|>) in very magic (non-capturing)
          table.insert(result, '%(<|>)')
        end
      elseif next_char == 'B' then
        -- Non-word boundary: vimgrep syntax has no direct equivalent; it could
        -- be approximated as a negated boundary check using Vim assertions, but
        -- this would be beyond the scope of the plugin for a rarely used regex
        -- feature.
        table.insert(warnings, '\\B not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      elseif next_char == 'A' then
        -- \A (start of string in ripgrep) is equivalent to ^ under our constraints:
        --   * no multiline patterns
        --   * no PCRE2 (default rg engine only)
        --   * line-oriented matching
        -- Using Vim's \%^ would introduce buffer-level semantics and subtle
        -- differences (e.g. EOF newline handling), so we deliberately map \A -> ^.
        table.insert(result, '^')
        table.insert(warnings, '\\A treated as ^')
      elseif next_char == 'z' then
        -- \z (end of string in ripgrep) is equivalent to $ under our constraints.
        -- Mapping to Vim's \%$ would be incorrect: \%$ matches the absolute end of
        -- the buffer, which fails when a file ends with a newline (the common case).
        -- To preserve ripgrep semantics, we map \z -> $.
        table.insert(result, '$')
        table.insert(warnings, '\\z treated as $')
      elseif next_char == 'p' or next_char == 'P' then
        -- Unicode property classes: no reliable, portable 1:1 mapping from ripgrep to vimgrep.
        table.insert(warnings, 'unicode properties not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      elseif next_char:match('[1-9]') then
        -- Backreferences require PCRE2 in ripgrep, which we disallow.
        table.insert(warnings, 'backreferences require PCRE2')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      else
        -- All other escapes pass through (very magic escaping matches ripgrep)
        table.insert(result, '\\')
        table.insert(result, next_char)
      end
      i = i + 2
    elseif (char == '<' or char == '>') and not in_char_class then
      -- Angle brackets are literal in ripgrep but word boundaries in very magic
      table.insert(result, '\\')
      table.insert(result, char)
      i = i + 1
    elseif char == '[' and not in_char_class then
      -- Start of character class: pre-compute wordness for when we exit
      pending_class_wordness = M._classify_char_class_wordness(pattern:sub(i)) or M._wordness.unknown
      in_char_class = true
      table.insert(result, '[')
      i = i + 1

      -- Handle special positions: ^, ], ^]
      if pattern:sub(i, i) == '^' then
        table.insert(result, '^')
        i = i + 1
      end
      if pattern:sub(i, i) == ']' then
        table.insert(result, ']')
        i = i + 1
      end
    elseif char == ']' and in_char_class then
      -- End of character class: apply the pre-computed wordness and skip
      -- end-of-loop wordness tracking (which would incorrectly classify ']')
      in_char_class = false
      wordness_before = pending_class_wordness
      pending_class_wordness = nil
      table.insert(result, ']')
      i = i + 1
      goto continue
    elseif char == '{' and not in_char_class then
      -- Non-greedy brace quantifier: {n}? {n,}? {n,m}? -> {-n} {-n,} {-n,m}
      -- Handle it as an independent subsequence, so we can account for ? at
      -- the end without backtracking on the main sequence.
      -- Find the opening brace in the result and insert '-' after it.
      local subresult = {}
      while i <= len do
        -- collect and advance in any case
        local qch, next_qch = pattern:sub(i, i), pattern:sub(i + 1, i + 1)
        table.insert(subresult, qch)
        i = i + 1

        -- if this was the closing of a brace identifer, handle it
        if qch == '}' then
          was_quantifier = true
          if next_qch == '?' then
            -- this is a non-greedy brace quantifier: insert the '-' character
            -- after the opening brace: {4,7} => {-4,7} and consume the '?' in
            -- the source
            table.insert(subresult, 2, '-')
            i = i + 1
          end
          -- merge the subsequence back into the main result
          for j = 1, #subresult do
            table.insert(result, subresult[j])
          end
          -- end the brace quantifier sequence
          break
        end
      end
    elseif (char == '*' or char == '+' or char == '?')
        and next_char == '?'
        and not in_char_class
        and i > 1 then
      -- Non-greedy quantifier: *? +? ?? (as long as it's not the first character).
      if char == '*' then
        table.insert(result, '{-}')
      elseif char == '+' then
        table.insert(result, '{-1,}')
      else -- char == '?'
        table.insert(result, '{-0,1}')
      end
      i = i + 2
    elseif (char == '*' or char == '+' or char == '?')
        and next_char == '+'
        and not in_char_class then
      -- Possessive quantifiers: no Vim equivalent
      table.insert(warnings, 'possessive quantifiers not supported')
      return { pattern = nil, warning = M._format_warnings(warnings) }
    elseif char == '(' and next_char == '?' and not in_char_class then
      local third_char = pattern:sub(i + 2, i + 2)
      if third_char == ':' then
        -- Non-capturing group: (?:...) -> %(...)
        table.insert(result, '%(')
        i = i + 3 -- skip (?:
      elseif third_char == 'P' and pattern:sub(i + 3, i + 3) == '<' then
        -- Named capture group (Python style): (?P<name>...) -> (...)
        -- Vim doesn't support named captures, but we can translate it to a
        -- numbered capture group.
        table.insert(result, '(')
        local name_start = i + 4
        local name_end = pattern:find('>', name_start, true)
        if not name_end or name_end == name_start then
          table.insert(warnings, 'invalid group name')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        table.insert(warnings, 'named groups become numbered')
        i = name_end + 1 -- continue after '>'
      elseif third_char == '<' then
        local fourth_char = pattern:sub(i + 3, i + 3)
        -- (?<=...) and (?<!...) are lookbehinds, not named captures.
        -- Not supported, see below: Lookarounds.
        if fourth_char == '=' or fourth_char == '!' then
          table.insert(warnings, 'lookarounds not supported')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        -- Named capture group (PCRE style): (?<name>...) -> (...)
        table.insert(result, '(')
        local name_start = i + 3
        local name_end = pattern:find('>', name_start, true)
        if not name_end or name_end == name_start then
          table.insert(warnings, 'invalid group name')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        table.insert(warnings, 'named groups become numbered')
        i = name_end + 1 -- continue after '>'
      else
        -- Lookarounds: Vim has equivalents (\@=, \@!, \@<=, \@<!), however since
        -- ripgrep's default engine doesn't support lookarounds and we disallow
        -- PCRE2, we don't support them.
        --
        -- Atomic groups: no Vim equivalent.
        table.insert(warnings, 'lookarounds and atomic groups not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      end
    elseif char == '/' then
      -- Escape search delimiter
      table.insert(result, '\\/')
      i = i + 1
    elseif not in_char_class
        and (char == '=' or char == '~' or char == '@' or char == '&') then
      -- Literal in ripgrep, but special in very magic mode, need escaping.
      table.insert(result, '\\')
      table.insert(result, char)
      i = i + 1
    else
      -- Everything else passes through unchanged
      table.insert(result, char)
      i = i + 1
    end

    -- Determine wordness of current atom for boundary heuristics in subsequent
    -- iterations. Skip while inside character classes (wordness is assigned
    -- when we exit the class).
    if in_char_class then
      -- Do nothing: wordness will be set when we see ']'
    elseif char == '*' or char == '+' or char == '?' or was_quantifier then
      -- Quantifiers: preserve the preceding wordness (don't change wordness_before)
    elseif char == '.' then
      wordness_before = M._wordness.unknown
    elseif unknown_atoms[atom] then
      wordness_before = M._wordness.unknown
    elseif word_atoms[atom] or char:match('[%w]') then
      wordness_before = M._wordness.word
    elseif non_word_atoms[atom] or non_word_atoms_before[atom] or char:match('[^%w]') then
      wordness_before = M._wordness.non_word
    else
      wordness_before = M._wordness.unknown
    end

    ::continue::
  end

  local vimgrep_pattern = table.concat(result)
  -- Handle word-bounded searches
  if opts.word then
    vimgrep_pattern = '<' .. table.concat(result) .. '>'
  end
  -- Make the pattern "very magic"
  vimgrep_pattern = '\\v' .. vimgrep_pattern

  -- Case-sensitivity must be set at the beginning of the pattern, or it will be
  -- interpreted as an escaped character.
  if opts.case == types.search_case.sensitive then
    vimgrep_pattern = '\\C' .. vimgrep_pattern
  elseif opts.case == types.search_case.insensitive then
    vimgrep_pattern = '\\c' .. vimgrep_pattern
  end

  return { pattern = vimgrep_pattern, warning = M._format_warnings(warnings) }
end

--- Determine whether the given ripgrep pattern starts with character class,
--- and if the character class represents a word character, a non-word character,
--- or if it cannot be determined.
---
--- It works by exclusion, removing different types of atoms, and checking what
--- is left, until its wordness can be with some approximation inferred.
---
---@param pattern string
---@return wordness?
function M._classify_char_class_wordness(pattern)
  if not pattern:match('^%[') then
    return nil
  end

  local content = M._extract_leading_char_class(pattern)
  if not content then
    return M._wordness.unknown
  end

  -- A negated class potentially matches both word and non-word characters, so
  -- its wordness cannot be determined.
  if content:sub(1, 1) == '^' then
    return M._wordness.unknown
  end

  local remaining = content
  local next_remaining = content
  local had_word = false
  local had_non_word = false
  local had_ambiguous = false

  -- Check for non-word atoms: \s, \W
  next_remaining = remaining
      :gsub('\\[sW]', '')
  if next_remaining ~= remaining then had_non_word = true end
  remaining = next_remaining

  -- Check for word-char ranges (only the ones with same character cases,
  -- otherwise they would span punctuation)
  next_remaining = remaining
      :gsub('%u%-%u', '')
      :gsub('%l%-%l', '')
      :gsub('%d%-%d', '')
      :gsub('_%-_', '')
  if next_remaining ~= remaining then had_word = true end
  remaining = next_remaining

  -- Check for ambiguous negated atoms
  next_remaining = remaining
      :gsub('\\[SD]', '')
  if next_remaining ~= remaining then had_ambiguous = true end
  remaining = next_remaining

  -- Check for escaped word chars (\a, \_, \0, etc.) and for word-wise atoms (\w, \d)
  next_remaining = remaining
      :gsub('\\[%w_]', '')
      :gsub('\\[wd]', '')
  if next_remaining ~= remaining then had_word = true end
  remaining = next_remaining

  -- Check for literal word chars (note: Lua matches ASCII only, so we
  -- implicitely do not support unicode-aware word boundaries that ripgrep does.
  next_remaining = remaining
      :gsub('[%w_]', '')
  if next_remaining ~= remaining then had_word = true end
  remaining = next_remaining

  -- Check for other non-word atoms
  next_remaining = remaining
      :gsub('\\.', '')
      :gsub('%-', '')
      :gsub('^%]', '')
      :gsub('[^%w_]', '')
  if next_remaining ~= remaining then had_non_word = true end
  remaining = next_remaining

  -- Check for ranges that span punctuation
  next_remaining = remaining
      :gsub('%u%-%l', '')
  if next_remaining ~= remaining then had_ambiguous = true end
  remaining = next_remaining

  if had_ambiguous or remaining ~= '' then
    return M._wordness.unknown
  elseif had_word and had_non_word then
    return M._wordness.unknown
  elseif had_word then
    return M._wordness.word
  elseif had_non_word then
    return M._wordness.non_word
  else
    return M._wordness.unknown
  end
end

--- Extract the content of a leading character class from a regex pattern.
--- Returns the content between the brackets (excluding the brackets themselves),
--- or nil if the pattern doesn't start with a valid character class.
---
--- Handles edge cases:
--- - ] as first char (or after ^) is literal, not a closer
--- - \] is an escaped bracket, not a closer
--- - \\] is an escaped backslash followed by a closer
---
--- Extracting a ripgrep char class content cannot be done with Lua pattern
--- matching alone: due to how Lua string escapes work we would not be able to
--- reliably identify the closing `]` in all cases.
---
---@param s string
---@return string?
function M._extract_leading_char_class(s)
  if s:sub(1, 1) ~= '[' then
    return nil
  end

  -- Regex char-class rule: a ']' can be literal if it appears first
  -- (or first after '^' for negated classes). So skip it as a closer.
  local from = 2
  if s:sub(2, 2) == ']' then
    from = 3
  elseif s:sub(2, 2) == '^' and s:sub(3, 3) == ']' then
    from = 4
  end

  while true do
    local a, b, slashes = s:find('(\\*)]', from)
    if not a then
      return nil
    end

    if #slashes % 2 == 0 then
      local close = a + #slashes
      return s:sub(2, close - 1)
    end

    from = b + 1
  end
end

--- Formats accumulated warnings into a single message.
---
---@param warnings string[] List of warning messages
---@return string|nil warning Formatted warning or nil if empty
function M._format_warnings(warnings)
  if #warnings == 0 then
    return nil
  elseif #warnings == 1 then
    return warnings[1]
  else
    return warnings[1] .. string.format(' (+%d more)', #warnings - 1)
  end
end

return M
