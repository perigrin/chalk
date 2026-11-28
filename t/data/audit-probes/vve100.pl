my %h = (k=>{v=>1}); sub f { $h{k}{v} = 5; $_[0] } print f($h{k}{v}), "\n";
