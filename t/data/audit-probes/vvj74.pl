my @a = ([1,2],[3,4]); my @t = map { [reverse @$_] } @a; print $a[0][0], $t[0][0], "\n";
