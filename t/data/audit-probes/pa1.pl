our @g; sub add { push @g, $_[0]; return } my $a = @g ? 1 : 0; add("k"); my $b = @g ? 1 : 0; print "$a $b\n";
