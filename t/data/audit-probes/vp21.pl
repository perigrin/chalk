my %h = (a => "p"); my $x = $h{a} . ($h{a} = "q"); print "$x\n";
