our @g = (1,2); my %h = (list => [@g], n => scalar(@g)); push @g, 3; print "@{$h{list}} $h{n}\n";
