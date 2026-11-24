my %h; sub f {} f($h{x}); print exists $h{x}?1:0,"\n";
