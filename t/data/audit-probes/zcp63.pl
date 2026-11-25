my @a=(1,2); sub mk { my $l=[@_]; $l } my $l=mk(@a); $a[0]=9; print "@$l\n";
