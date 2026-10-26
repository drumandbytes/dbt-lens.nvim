return require('telescope').register_extension({
  exports = {
    models = function() require('dbt_lens').command({ fargs = { 'models' } }) end,
  },
})
