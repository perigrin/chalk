our %h = (a=>1); { local %h; print scalar(keys %h); $h{b} = 1 } print join(",", sort keys %h), "\n";
