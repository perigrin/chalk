my @p=split //, "abc"; my @q=split /,/, "a,b,,,"; my @r=split /,/, ",a"; my @s=split " ", "  a b "; print scalar(@p), scalar(@q), scalar(@r), scalar(@s), "\n";
