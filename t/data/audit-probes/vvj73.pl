my @a = ([1,2],[3,4]); for my $r (@a) { push @$r, 0 } print scalar(@{$a[1]}), "\n";
