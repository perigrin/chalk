my @a; for my $x (@a[1..2]) { } my %h; for my $v (@h{qw(a b)}) { } print scalar(@a), scalar(keys %h), "\n";
