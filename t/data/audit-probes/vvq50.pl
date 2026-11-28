my %h = (a=>[1,2]); my @l = (0, @{$h{a}}); push @{$h{a}}, 3; print "@l\n";
