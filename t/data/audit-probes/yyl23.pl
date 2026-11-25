print join("|", split //, "abc"), " ", join("|", split /,/, "a,b,,c,,"), " ", join("|", split /,/, "a,b,,c,,", -1), " ", join("|", split " ", "  a b  "), "\n";
