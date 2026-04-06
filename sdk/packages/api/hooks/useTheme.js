const { getTheme } = require("../runtime");

function useTheme() {
  return getTheme();
}

module.exports = {
  useTheme,
};
