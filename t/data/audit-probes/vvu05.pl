my %h = (k=>"a"); sub f { if ($_[0]) { $h{$h{k}} = 7 } else { $h{z} = 8 } } print f(1), f(0), "\n";
