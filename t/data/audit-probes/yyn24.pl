my $w = 0; local $SIG{__WARN__} = sub { $w++ }; { use warnings; my @a = (1); my $x = $a[5] + 1; my $y = "abc" + 1; my %h; my $z = $h{k} . "x"; } print "$w\n";
