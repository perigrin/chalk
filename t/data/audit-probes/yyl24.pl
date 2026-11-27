print join("|", split /(,)/, "a,b"), " ", join("|", split /,/, ",a"), " ", join("|", split /,/, "a,b,c", 2), " ", scalar(my @p = split /,/, ""), " ", join("|", split /\s*,\s*/, "a , b,c"), "\n";
