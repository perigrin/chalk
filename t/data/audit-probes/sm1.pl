my $i = 0; $i++ while $i < 5; my @a; push @a, $_ for 1..3; print "$i @a\n" if $i; print "u\n" unless @a;
