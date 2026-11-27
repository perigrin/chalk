my %h; sub ph { $h{k} = 1 } my @l = (exists $h{k} ? 1 : 0, ph(), exists $h{k} ? 1 : 0); print "@l\n";
