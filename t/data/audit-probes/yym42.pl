my @a = (1,2,3,4,5,6); my @ch; push @ch, [splice(@a, 0, 2)] while @a; my @fl = map { @$_ } @ch; my @rv = map { [reverse @$_] } @ch; print scalar(@ch), "@fl", join("|", map { "@$_" } @rv), "\n";
