package P; our %h = (a=>1); package main; { local %P::h = (b=>2); } print join(",", keys %P::h), "\n";
