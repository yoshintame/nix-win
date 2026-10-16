_:
let
  mk = type: value: {
    _type = "regValue";
    inherit type value;
  };
in
{
  dword = mk "dword";
  string = mk "sz";
  expandString = mk "expand";
  multiString = mk "multi";
  qword = mk "qword";
  binary = mk "binary";
}
