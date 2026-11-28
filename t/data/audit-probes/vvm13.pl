our %h = (a=>1); { local %h = (); } print scalar(keys %h), "\n";
