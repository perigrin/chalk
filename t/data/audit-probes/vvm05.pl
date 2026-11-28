our %h = (a=>1); { local %h; $h{a} = 5 } print $h{a}, "\n";
