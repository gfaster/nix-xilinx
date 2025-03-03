pkgs:
let
plugins = with pkgs.vimPlugins; [
  vim-fugitive
  vim-sleuth
  neodev-nvim
  nvim-lspconfig
  nvim-cmp
  kanagawa-nvim
  fidget-nvim
  luasnip
  cmp_luasnip
  cmp-nvim-lsp
  lualine-nvim
  comment-nvim
  vim-surround
  vim-repeat
  plenary-nvim
  telescope-nvim
  telescope-fzf-native-nvim
  nvim-treesitter.withAllGrammars
  nvim-treesitter-textobjects
  gitsigns-nvim
  indent-blankline-nvim
];
in
pkgs.vimPlugins.vimUtils.packDir ({my-nvim = {start = plugins; }; })
# vimUtils.packDir (plugins)
