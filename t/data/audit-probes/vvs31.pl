my $r = \(my $v = "a"); $$r = "$$r$$r"; print "$v\n";
