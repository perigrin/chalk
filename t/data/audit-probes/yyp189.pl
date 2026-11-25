my @a=("ab"); sub t { $a[0] =~ tr/a/z/ } my @c=@a; t(); print "@c@a\n";
