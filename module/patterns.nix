{
  line = "[^\r\n\t]*";
  plain = "[^\r\n\t\"]+";
  name = "[A-Za-z0-9._-]+";
  capability = "[A-Za-z0-9._~-]+";
  keyPath = "[^\\\\\r\n\t\"]+(\\\\[^\\\\\r\n\t\"]+)*";
  displayName = "[^\r\n\t\"']+";
  port = "[0-9,-]+";
  address = "[0-9A-Fa-f:./-]+";
  interfaceAlias = "[A-Za-z0-9 ._()-]+";
  grant = "\\*?[A-Za-z0-9-]+:\\(?[A-Z,]+\\)?";
  powerSetting = "[a-z-]+";
  word = "[A-Za-z]+";
  packageId = "[A-Za-z0-9][A-Za-z0-9._+-]*";
  location = "[A-Za-z]:\\\\[^\r\n\t\"]*[^\\\\\r\n\t\"]";
  absolutePath = "/[^\r\n\t]+";
}
