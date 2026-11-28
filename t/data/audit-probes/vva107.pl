our %h = (a=>1); { local $h{a} = 9; %h = (); print scalar(keys %h) } print join(",", %h), "\n";
