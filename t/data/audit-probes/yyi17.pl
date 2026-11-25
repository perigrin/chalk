sub inc { $_[0]++ } my @a=(1,2); my $r=\@a; inc(@$r); inc($r->[1]); inc($$r[1]); inc(${$r}[1]); print "@a\n";
