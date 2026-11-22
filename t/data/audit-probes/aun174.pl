my @a = ("b\n","c\n"); chomp(@a); my $r = \@a; chop(@$r); print join("|", @a), "\n";
