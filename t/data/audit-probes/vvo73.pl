my %h; sub z { $h{k} = 9; 0 } my @l = (($h{k} = 7), z()); print "@l\n";
