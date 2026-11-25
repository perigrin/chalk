my %h=(a=>"x"); my $s = $h{a} . ($h{a} = "z"); print "$s\n";
