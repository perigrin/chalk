my $s = "abc"; my $t = join "", sort { $b cmp $a } split //, $s; print "$t\n";
