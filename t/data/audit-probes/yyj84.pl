my @a=(1,2,3); my $r = \@a[1..2]; my $cnt = @{[ \(@a) ]}; my ($f) = map { \$_ } @a; $$f = 9; print "$$r $cnt @a\n";
