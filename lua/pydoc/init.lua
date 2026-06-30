local M = {}

local defaults = {
  python_cmd = 'python3',
  fallback = true,
}

local config = vim.deepcopy(defaults)

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
end

local function get_metadata_script()
  return [[
import importlib.metadata as md, sys
p = sys.argv[1]
try:
    m = md.metadata(p)
except md.PackageNotFoundError:
    for d in md.distributions():
        try:
            tl = d.read_text('top_level.txt')
            if tl and p in tl.splitlines():
                m = d.metadata
                break
        except Exception:
            continue
    else:
        sys.exit(1)
for e in (m.get_all('Project-URL') or []):
    l, _, u = e.partition(',')
    if l.strip().lower() == 'documentation':
        print(u.strip())
        sys.exit(0)
if 'Home-page' in m:
    print(m['Home-page'])
    sys.exit(0)
sys.exit(2)
]]
end

local function get_word_under_cursor()
  local word = vim.fn.expand('<cword>')
  if word == '' then return nil end
  return word
end

local function open_url(url)
  if vim.ui and vim.ui.open then
    vim.ui.open(url)
  else
    vim.fn.system({ 'xdg-open', url })
  end
end

local function extract_package(filepath)
  for _, pat in ipairs({ '/site-packages/', '/dist-packages/' }) do
    local idx = filepath:find(pat, 1, true)
    if idx then
      local rel = filepath:sub(idx + #pat)
      local pkg = rel:match('^([^/\\]+)')
      if pkg then
        pkg = pkg:gsub('%.dist%-info$', '')
        pkg = pkg:gsub('%.egg%-info$', '')
        pkg = pkg:gsub('%-[0-9].*$', '')
        return pkg
      end
    end
  end
  return nil
end

local function resolve_package_from_lsp()
  if not vim.lsp or not vim.lsp.buf_request_sync then
    return nil
  end
  local clients = vim.lsp.get_active_clients({ bufnr = 0 })
  if #clients == 0 then
    return nil
  end
  local params = vim.lsp.util.make_position_params()
  local ok, results = pcall(vim.lsp.buf_request_sync, 0, 'textDocument/definition', params, 1000)
  if not ok or not results or #results == 0 then
    return nil
  end
  local result
  for _, response in pairs(results) do
    result = response.result
    if result then break end
  end
  if not result then
    return nil
  end
  local uri = result.uri or (type(result) == 'table' and result.targetUri) or nil
  if not uri then
    return nil
  end
  return extract_package(vim.uri_to_fname(uri))
end

function M.open_docs(pkg)
  if not pkg then
    pkg = resolve_package_from_lsp() or get_word_under_cursor()
  end
  if not pkg then
    vim.notify('[pydoc] No package name found under cursor', vim.log.levels.WARN)
    return
  end

  local script = get_metadata_script()
  local cmd = string.format('%s -c %s %s 2>&1', config.python_cmd, vim.fn.shellescape(script), vim.fn.shellescape(pkg))
  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code == 1 then
    vim.notify(string.format('[pydoc] Package "%s" not found in Python environment', pkg), vim.log.levels.WARN)
    return
  elseif exit_code == 2 then
    vim.notify(string.format('[pydoc] No documentation URL found for "%s"', pkg), vim.log.levels.WARN)
    return
  elseif exit_code ~= 0 then
    local lines = vim.split(stdout, '\n', { plain = true })
    vim.notify(('[pydoc] Python error (exit=%d): %s'):format(exit_code, lines[1] or stdout), vim.log.levels.ERROR)
    return
  end

  local url = vim.trim(stdout)
  if url ~= '' then
    vim.notify(string.format('[pydoc] Opening: %s', url), vim.log.levels.INFO)
    open_url(url)
  end
end

function M.complete(arglead, _, _)
  local script = [[import importlib.metadata as md; print(' '.join(sorted(d.metadata['Name'] for d in md.distributions())))]]
  local cmd = string.format('%s -c %s', config.python_cmd, vim.fn.shellescape(script))
  local stdout = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then return {} end
  local packages = vim.split(vim.trim(stdout), ' ')
  return vim.tbl_filter(function(pkg)
    return pkg:lower():find(arglead:lower(), 1, true) == 1
  end, packages)
end

vim.api.nvim_create_user_command('PydocOpen', function(opts)
  if opts.args and opts.args ~= '' then
    M.open_docs(opts.args)
  else
    M.open_docs()
  end
end, {
  nargs = '?',
  complete = function(arglead, cmdline, cursorpos)
    return M.complete(arglead, cmdline, cursorpos)
  end,
})

vim.keymap.set('n', '<leader>pd', function()
  M.open_docs()
end, { desc = 'Open Python package documentation' })

return M
