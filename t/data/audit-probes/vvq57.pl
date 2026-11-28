my %h = (a=>[1,2]); my $s = join(",", @{$h{a}}, "x"); push @{$h{a}}, 3; print "$s\n";
