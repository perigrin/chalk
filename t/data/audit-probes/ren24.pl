my %h=(a=>[1]); my %c=%h; $c{a}=[2]; print "@{$h{a}}\n";
