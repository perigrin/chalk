my @a = map { $_ * $_ } grep { $_ % 2 } 1..5; my $s = join "+", @a; print "$s\n";
