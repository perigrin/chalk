my %h = (a=>[1,2]); my $r = [@{$h{a}}, "x"]; push @{$h{a}}, 3; print "@$r\n";
