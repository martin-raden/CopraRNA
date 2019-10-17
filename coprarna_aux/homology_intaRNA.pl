#!/usr/bin/env perl

use strict;
use warnings;
use Cwd 'abs_path'; 

# get absolute path
my $ABS_PATH = abs_path($0); 
# remove script name at the end
# match all non slash characters at the end of the string
$ABS_PATH =~ s|[^/]+$||g; 
my $PATH_COPRA_SUBSCRIPTS = $ABS_PATH;

# files dedicated to capture output of subcalls for debugging
my $OUT_STD = "CopraRNA2_subprocess.out";
my $OUT_ERR = "CopraRNA2_subprocess.err";

my $ncrnas = $ARGV[0]; # input_sRNA.fa
my $upfromstartpos = $ARGV[1]; # 200
my $down = $ARGV[2]; # 100
my $mrnapart = $ARGV[3]; # cds or 5utr or 3utr
my $GenBankFiles = "";
my $orgcount = 0;

my $cores = `grep 'core count:' CopraRNA_option_file.txt | grep -oP '\\d+'`; 
chomp $cores;

# check if CopraRNA1 prediction should be made
my $cop1 = `grep 'CopraRNA1:' CopraRNA_option_file.txt | sed 's/CopraRNA1://g'`; 
chomp $cop1;

# check nooi switch
my $nooi = `grep 'nooi:' CopraRNA_option_file.txt | sed 's/nooi://g'`; 
chomp $nooi;

# check for verbose printing
my $verbose = `grep 'verbose:' CopraRNA_option_file.txt | sed 's/verbose://g'`; 
chomp $verbose;

# get amount of top predictions to return
my $topcount = `grep 'top count:' CopraRNA_option_file.txt | grep -oP '\\d+'`;
chomp $topcount;
$topcount++; # need this to include the header

# check for websrv output printing
my $websrv = `grep 'websrv:' CopraRNA_option_file.txt | sed 's/websrv://g'`; 
chomp $websrv;

# check for enrichment on/off and count
my $enrich = `grep 'enrich:' CopraRNA_option_file.txt | sed 's/enrich://g'`; 
chomp $enrich;

# get window size option
my $winsize = `grep 'win size:' CopraRNA_option_file.txt | sed 's/win size://g'`; 
chomp $winsize;

# get maximum base pair distance 
my $maxbpdist = `grep 'max bp dist:' CopraRNA_option_file.txt | sed 's/max bp dist://g'`; 
chomp $maxbpdist;

# get consensus prediction option
my $cons = `grep 'cons:' CopraRNA_option_file.txt | sed 's/cons://g'`; 
chomp $cons;

# get ooifilt
my $ooi_filt = `grep 'ooifilt:' CopraRNA_option_file.txt | sed 's/ooifilt://g'`;
chomp $ooi_filt;

open ERRORLOG, ">>err.log" or die("\nError: cannot open file err.log in homology_intaRNA.pl\n\n"); 

my $keggtorefseqnewfile = $PATH_COPRA_SUBSCRIPTS . "kegg2refseqnew.csv";
# RefSeqID -> space separated RefSeqIDs // 'NC_005140' -> 'NC_005139 NC_005140 NC_005128'
my %refseqaffiliations = ();

# read kegg2refseqnew.csv
open(MYDATA, $keggtorefseqnewfile) or die("\nError: cannot open file $keggtorefseqnewfile in homology_intaRNA.pl\n\n");
    my @keggtorefseqnew = <MYDATA>;
close MYDATA;

# get the refseq affiliations
foreach(@keggtorefseqnew) {
    # split off quadruplecode (pseudokegg id)
    my @split = split("\t", $_);
    my $all_refseqs = $split[1];
    chomp $all_refseqs;
    # split up refseq ids
    my @split_refseqs = split(/\s/, $all_refseqs);
    foreach(@split_refseqs) {
        $refseqaffiliations{$_} = $all_refseqs;
    }
}

# add "ncRNA_" to fasta headers
system "sed 's/>/>ncRNA_/g' $ncrnas > ncrna.fa"; 

# assign correct refseq IDs for each sequence
for (my $i=4;$i<scalar(@ARGV);$i++) {
    # split up the refseq list for one organism
    my @split = split(/\s/, $refseqaffiliations{$ARGV[$i]});
    # get the first id entry
    my $first_refseq_id = $split[0];
    # override in ncrna.fa
    system "sed -i 's/$ARGV[$i]/$first_refseq_id/g' ncrna.fa";
}

# override $ncrnas variable
$ncrnas = "ncrna.fa";

# get Orgcount
$orgcount = (scalar(@ARGV) - 4);

## prepare input for combine_clusters.pl
## Download Refseq files by Refseq ID 
my $RefSeqIDs = `grep ">" input_sRNA.fa | tr '\n' ' ' | sed 's/>//g'`; 
my @split_RefIds = split(/\s+/, $RefSeqIDs);

foreach(@split_RefIds) {
    my $currRefSeqID = $_;

    my $presplitreplicons = $refseqaffiliations{$currRefSeqID};
    my @replikons = split(/\s/, $presplitreplicons);
    
    foreach(@replikons) {
        my $refseqoutputfile = $_ . ".gb"; # added .gb
        $GenBankFiles = $GenBankFiles . $refseqoutputfile . ",";
        my $accessionnumber = $_;
        print $PATH_COPRA_SUBSCRIPTS  . "get_refseq_from_refid.pl -acc $accessionnumber -g $accessionnumber.gb \n" if ($verbose); 
        system $PATH_COPRA_SUBSCRIPTS . "get_refseq_from_refid.pl -acc $accessionnumber -g $accessionnumber.gb";
    }
    chop $GenBankFiles;
    $GenBankFiles = $GenBankFiles . " ";
}

## RefSeq correct download check for 2nd try
my @files = ();
@files = <*gb>;

foreach(@files) {
    open(GBDATA, $_) or die("\nError: cannot open file $_ in homology_intaRNA.pl\n\n");
        my @gblines = <GBDATA>;
    close GBDATA;

    my $lastLine = $gblines[-2]; 
    my $lastLine_new = $gblines[-1]; 
    if ($lastLine =~ m/^\/\//) {
        # all is good
    } elsif ($lastLine_new =~ m/^\/\//) {
        # all is good
    } else {
        system "rm -f $_"; # remove file to try download again later
    }
}

## refseq availability check
@files = ();

my @totalrefseqFiles = split(/\s|,/, $GenBankFiles);
my $consistencyswitch = 1;

my $limitloops = 0;

my $sleeptimer = 30; 
while($consistencyswitch) {
    @files = ();
    @files = <*gb>;
    foreach(@totalrefseqFiles) {
        chomp $_;
        my $value = $_;
        if(grep( /^$value$/, @files )) { 
            $consistencyswitch = 0;
        } else {
             $limitloops++;
             $consistencyswitch = 1;
 
             if($limitloops > 100) { 
                 $consistencyswitch = 0;
                 print ERRORLOG "Not all RefSeq *gb files downloaded correctly. Restart your job.\n"; 
                 last;
             }
             my $accNr = $_;
             chop $accNr;
             chop $accNr;
             chop $accNr;
             sleep $sleeptimer; 
             $sleeptimer = $sleeptimer * 1.1; 
             print "next try: " . $PATH_COPRA_SUBSCRIPTS . "get_refseq_from_refid.pl -acc $accNr -g $accNr.gb\n" if ($verbose); 
             system $PATH_COPRA_SUBSCRIPTS . "get_refseq_from_refid.pl -acc $accNr -g $accNr.gb"; 
             last;
        }
    }
}

### end availability check


### refseq correct DL check kill job 
@files = <*gb>;

foreach(@files) {
    open(GBDATA, $_) or die("\nError: cannot open file $_ in homology_intaRNA.pl\n\n");
        my @gblines = <GBDATA>;
    close GBDATA;

    my $lastLine = $gblines[-2]; 
    my $lastLine_new = $gblines[-1]; 
    if ($lastLine =~ m/^\/\//) {
        # all is good
    } elsif ($lastLine_new =~ m/^\/\//) {
        # all is good
    } else {
        print ERRORLOG "File $_ did not download correctly. This is probably due to a connectivity issue on your or the NCBI's side. Please try to resubmit your job later (~2h.).\n"; # kill
    }
}


## fixing issue with CONTIG and ORIGIN both in gbk file (can't parse without this) 

@files = <*gb>;

foreach (@files) {
    system "sed -i '/^CONTIG/d' $_"; ## d stands for delete
}

#### end quickfix


@files = <*gb>;

foreach (@files) {
    system $PATH_COPRA_SUBSCRIPTS . "check_for_gene_CDS_features.pl $_ >> gene_CDS_exception.txt";
}

open(MYDATA, "gene_CDS_exception.txt") or die("\nError: cannot open file gene_CDS_exception.txt at homology_intaRNA.pl\n\n");
    my @exception_lines = <MYDATA>;
close MYDATA;


if (scalar(@exception_lines) >= 1) {
    my $exceptionRefSeqs = "";
    foreach(@exception_lines) {
        my @split = split(/\s+/,$_);
        $exceptionRefSeqs = $exceptionRefSeqs . $split[-1] . " ";
    }
    print ERRORLOG "Error: gene but no CDS features present in $exceptionRefSeqs.\n This is most likely connected to currently corrupted RefSeq record(s) at the NCBI.\nPlease resubmit your job without the currently errorous organism(s) or wait some time with your resubmission.\nUsually the files are fixed within ~1 week.\n"; 
}
## end CDS gene exception check


## get cluster.tab with DomClust
unless (-e "cluster.tab") { # only do if cluster.tab has not been imported

    ### get AA fasta for homolog clustering

    @files = <*gb>;

    foreach(@files) {
        system $PATH_COPRA_SUBSCRIPTS . "get_CDS_from_gbk.pl $_ >> all.fas"; 
    }

    # prep for DomClust
    system "formatdb -i all.fas" unless (-e "all.fas.blast"); 
    # blast sequences
    system "blastall -a $cores -p blastp -d all.fas -e 0.001 -i all.fas -Y 1e9 -v 30000 -b 30000 -m 8 -o all.fas.blast 2>> $OUT_ERR" unless (-e "all.fas.blast"); # change the -a parameter to qdjust core usage 
    # remove empty error file
    system $PATH_COPRA_SUBSCRIPTS . "blast2homfile.pl all.fas.blast > all.fas.hom"; 
    system $PATH_COPRA_SUBSCRIPTS . "fasta2genefile.pl all.fas";
    # DomClust
    my $domclustExitStatus = system "domclust all.fas.hom all.fas.gene -HO -S -c60 -p0.5 -V0.6 -C80 -o5 > cluster.tab 2>> ".$OUT_ERR;
    $domclustExitStatus /= 256; # get original exit value
    # ensure domclust went fine
    if ($domclustExitStatus != 0) {
    	# restart domclust with --nobreak option
	    my $domclustExitStatus = system "domclust all.fas.hom all.fas.gene -HO -S -c60 -p0.5 -V0.6 -C80 -o5 --nobreak > cluster.tab 2>> $OUT_ERR"; 
	    $domclustExitStatus /= 256; # get original exit value
	    # check if second run was successful
	    if ($domclustExitStatus != 0) {
	    	die("\nERROR: 'domclust' returned with non-zero exit status $domclustExitStatus.\n\n");
	    }
    }

    
    system "grep '>' all.fas | uniq -d > duplicated_CDS.txt";
    if (-s "duplicated_CDS.txt") {
        print ERRORLOG "duplicated CDS for some genes. Please check locus tags:\n";
		my $fileContent = do{local(@ARGV,$/)="duplicated_CDS.txt";<>};
		print ERRORLOG $fileContent . "\n";
    }

}

# 16s sequence parsing 
print $PATH_COPRA_SUBSCRIPTS . "parse_16s_from_gbk.pl $GenBankFiles > 16s_sequences.fa\n" if ($verbose);
system $PATH_COPRA_SUBSCRIPTS . "parse_16s_from_gbk.pl $GenBankFiles > 16s_sequences.fa" unless (-e "16s_sequences.fa");

# check 16s
open(MYDATA, "16s_sequences.fa") or die("\nError: cannot open file 16s_sequences.fa in homology_intaRNA.pl\n\n");
    my @sixteenSseqs = <MYDATA>;
close MYDATA;

my $sixteenScounter = 0;
my $temp_16s_ID = ""; 
foreach (@sixteenSseqs) {
    if ($_ =~ m/>/) {
        $temp_16s_ID = $_; 
        chomp $temp_16s_ID;
        $sixteenScounter++;
    } else {
        if ($_ =~ m/N/) { print ERRORLOG "\nError: 'N' characters present in 16s_sequences.fa. Remove $temp_16s_ID from the input for the job to execute correctly.\n"; }
    }
}

if ($sixteenScounter ne $orgcount) {
    my $no16sOrgs = `(grep ">" 16s_sequences.fa && grep ">" input_sRNA.fa) | sort | uniq -u | tr '\n' ' '`; 
    chomp $no16sOrgs;
    print ERRORLOG "\nError: wrong number of sequences in 16s_sequences.fa.\nOne (or more) of your entered organisms does not contain a correctly annotated 16s rRNA sequence and needs to be removed.\nPlease remove $no16sOrgs\n";
}

## prepare single organism whole genome target predictions 
system "echo $GenBankFiles > merged_refseq_ids.txt"; # need this for iterative region plot construction

my $prepare_intarna_out_call = $PATH_COPRA_SUBSCRIPTS . "prepare_intarna_out.pl $ncrnas $upfromstartpos $down $mrnapart $GenBankFiles";
print $prepare_intarna_out_call . "\n" if ($verbose);
system $prepare_intarna_out_call;
## end

# re-cluster based on 5'UTRs
system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "refine_clustertab.r"; 

# do CopraRNA combination 
print $PATH_COPRA_SUBSCRIPTS . "combine_clusters.pl $orgcount\n" if ($verbose);
system $PATH_COPRA_SUBSCRIPTS . "combine_clusters.pl $orgcount";

# make annotations
system $PATH_COPRA_SUBSCRIPTS . "annotate_raw_output.pl CopraRNA1_with_pvsample_sorted.csv opt_tags.clustered_rcsize $GenBankFiles > CopraRNA1_anno.csv" if ($cop1); 
system $PATH_COPRA_SUBSCRIPTS . "annotate_raw_output.pl CopraRNA2_prep_sorted.csv opt_tags.clustered $GenBankFiles > CopraRNA2_prep_anno.csv";

# get additional homologs in cluster.tab
system $PATH_COPRA_SUBSCRIPTS . "parse_homologs_from_domclust_table.pl CopraRNA1_anno.csv cluster.tab > CopraRNA1_anno_addhomologs.csv" if ($cop1); 
system $PATH_COPRA_SUBSCRIPTS . "parse_homologs_from_domclust_table.pl CopraRNA2_prep_anno.csv cluster.tab > CopraRNA2_prep_anno_addhomologs.csv"; 

# add corrected p-values (padj) - first column
system "awk -F',' '{ print \$1 }' CopraRNA1_anno_addhomologs.csv > CopraRNA1_pvalues.txt" if ($cop1); 
# just for formatting
system "awk -F',' '{ print \$1 }' CopraRNA2_prep_anno_addhomologs.csv > CopraRNA2_pvalues.txt";

system "R --slave -f $PATH_COPRA_SUBSCRIPTS/calc_padj.R --args CopraRNA1_pvalues.txt" if ($cop1);
system "paste padj.csv CopraRNA1_anno_addhomologs.csv -d ',' > CopraRNA1_anno_addhomologs_padj.csv" if ($cop1); 

# just for formatting
system "R --slave -f $PATH_COPRA_SUBSCRIPTS/calc_padj.R --args CopraRNA2_pvalues.txt";
system "paste padj.csv CopraRNA2_prep_anno_addhomologs.csv -d ',' > CopraRNA2_prep_anno_addhomologs_padj.csv"; 

# add amount sampled values CopraRNA 1 // CopraRNA 2 has no sampling
system $PATH_COPRA_SUBSCRIPTS . "get_amount_sampled_values_and_add_to_table.pl CopraRNA1_anno_addhomologs_padj.csv 0 > CopraRNA1_anno_addhomologs_padj_amountsamp.csv" if ($cop1); 
# make consistent names
system "mv CopraRNA1_anno_addhomologs_padj_amountsamp.csv CopraRNA1_final_all.csv" if ($cop1); 
system $PATH_COPRA_SUBSCRIPTS . "get_amount_sampled_values_and_add_to_table.pl CopraRNA2_prep_anno_addhomologs_padj.csv 1 > CopraRNA2_prep_anno_addhomologs_padj_amountsamp.csv"; 

# get ooi refseq id
my @split = split(/\s/, $refseqaffiliations{$ARGV[4]});
# get the first id entry
my $ooi_refseq_id = $split[0];



unless ($cop1) {
    # align homologous targets
    system $PATH_COPRA_SUBSCRIPTS . "parallelize_target_alignments.pl CopraRNA2_prep_anno_addhomologs_padj_amountsamp.csv";
    # run position script
    system "cp " . $PATH_COPRA_SUBSCRIPTS . "CopraRNA_available_organisms.txt ."; 
    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "copraRNA2_phylogenetic_sorting.r 2>> $OUT_ERR >> $OUT_STD"; 
    # perform actual CopraRNA 2 p-value combination
    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "join_pvals_coprarna_2.r 2>> $OUT_ERR >> $OUT_STD"; 
    
}


# truncate final output // 
system "head -n $topcount CopraRNA1_final_all.csv > CopraRNA1_final.csv" if ($cop1); 
unless ($cop1) {
    system "head -n $topcount CopraRNA_result_all.csv > CopraRNA_result.csv"; 
    #system "head -n $topcount CopraRNA2_final_all_balanced.csv > CopraRNA2_final_balanced.csv"; 
    #system "head -n $topcount CopraRNA2_final_all_balanced_consensus.csv > CopraRNA2_final_balanced_consensus.csv"; 
    #system "head -n $topcount CopraRNA2_final_all_ooi_consensus.csv > CopraRNA2_final_ooi_consensus.csv"; 
    #system "head -n $topcount CopraRNA2_final_all_ooi_ooiconsensus.csv > CopraRNA2_final_ooi_ooiconsensus.csv"; 
}

# filtering for ooi single p-value
if ($ooi_filt) {

    my @not_filtered_list = (); # values below the p-value threshold
    my @filtered_list = ();     # values empty or above the p-value threshold

    open(MYDATA, "CopraRNA_result_all.csv") or die("\nError: cannot open file CopraRNA_result_all.csv at homology_intaRNA.pl\n\n");
        my @CopraRNA_all_out_lines = <MYDATA>;
    close MYDATA;

    push(@not_filtered_list, $CopraRNA_all_out_lines[0]); # header

    for (my $i=1;$i<scalar(@CopraRNA_all_out_lines);$i++) {
        my $curr_line = $CopraRNA_all_out_lines[$i];
        my @split = split(/,/,$curr_line);
        my $curr_ooi_cell = $split[2];
        if ($curr_ooi_cell) {
            my @split_ooi_cell = split(/\|/,$curr_ooi_cell);
            my $curr_ooi_pv = $split_ooi_cell[2];
            if($curr_ooi_pv<=$ooi_filt) { # smaller or eq to the set ooi_filt threshold
                push(@not_filtered_list, $curr_line);
            } else { # bigger tahn the set ooi_filt threshold
                push(@filtered_list, $curr_line);
            }
        } else { # empty cell
            push(@filtered_list, $curr_line);
        }
    }
    # print
    open WRITEFILT, ">", "CopraRNA_result_all_filt.csv";

    foreach(@not_filtered_list) {
        print WRITEFILT $_;
    }
    foreach(@filtered_list) {
        print WRITEFILT $_;
    }
    close WRITEFILT;
    system "cp CopraRNA_result_all_filt.csv CopraRNA_result_all.csv";
    system "head -n $topcount CopraRNA_result_all.csv > CopraRNA_result.csv";
}

# plot CopraRNA 2 evo heatmap, jalview files for selection and prepare CopraRNA2 html output
unless ($cop1) {


    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "copraRNA2_find_conserved_sites.r 2>> $OUT_ERR >> $OUT_STD";
    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "copraRNA2_conservation_heatmaps.r 2>> $OUT_ERR >> $OUT_STD"; 
    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "CopraRNA2html.r 2>> $OUT_ERR >> $OUT_STD";
    system "rm -f CopraRNA_available_organisms.txt"; 
}

# check for run fail CopraRNA
open(MYDATA, "CopraRNA_result.csv") or die("\nError: cannot open file CopraRNA_result.csv at homology_intaRNA.pl\n\n");
    my @CopraRNA_out_lines = <MYDATA>;
close MYDATA;

if (scalar(@CopraRNA_out_lines) <= 1) { 
    print ERRORLOG "Error: No predictions in CopraRNA_result.csv. CopraRNA run failed.\n"; 
}

# trim off last column (initial_sorting) if CopraRNA 2 prediction mode
unless ($cop1) {
     system "awk -F',' '{ print \$NF }' CopraRNA_result.csv > CopraRNA_result.map_evo_align" if ($websrv);
     system "awk -F, -vOFS=, '{NF-=1;print}' CopraRNA_result.csv > CopraRNA_result_temp.csv";
     system "mv CopraRNA_result_temp.csv CopraRNA_result.csv";
     system "awk -F, -vOFS=, '{NF-=1;print}' CopraRNA_result_all.csv > CopraRNA_result_all_temp.csv";
     system "mv CopraRNA_result_all_temp.csv CopraRNA_result_all.csv";
     # change header
     system "sed -i 's/,Additional.homologs,/,Additional homologs,/g' CopraRNA_result.csv";
     system "sed -i 's/,Amount.sampled/,Amount sampled/g' CopraRNA_result.csv";
     system "sed -i 's/p.value/p-value/g' CopraRNA_result.csv";
     system "sed -i 's/,Additional.homologs,/,Additional homologs,/g' CopraRNA_result_all.csv";
     system "sed -i 's/,Amount.sampled/,Amount sampled/g' CopraRNA_result_all.csv";
     system "sed -i 's/p.value/p-value/g' CopraRNA_result_all.csv";
}

if ($websrv) { # only if webserver output is requested via -websrv 

    my $allrefs = $refseqaffiliations{$ARGV[4]};
    my @splitallrefs = split(/\s/,$allrefs);

    my $themainrefid = $splitallrefs[0]; # organism of interest RefSeq ID
    my $orgofintTargets = $themainrefid . "_upfromstartpos_" . $upfromstartpos . "_down_" . $down . ".fa";
    my $orgofintsRNA = "ncRNA_" . $themainrefid . ".fa";

    # returns comma separated locus tags (first is always refseq ID). Example: NC_000913,b0681,b1737,b1048,b4175,b0526,b1093,b1951,,b3831,b3133,b0886,,b3176 
    my $top_predictons_locus_tags = `awk -F',' '{print \$3}' CopraRNA_result.csv | sed 's/(.*)//g' | tr '\n' ','`; 

    # split
    my @split = split(/,/, $top_predictons_locus_tags);
    
    # remove RefSeqID
    shift @split;

    foreach (@split) {
        if ($_) {
            system "grep -iA1 '$_' $orgofintTargets >> CopraRNA_top_targets.fa";
        }
    }

    system "IntaRNA_1ui.pl -t CopraRNA_top_targets.fa -m $orgofintsRNA -o -w $winsize -L $maxbpdist > Cop_IntaRNA1_ui.intarna";
    # fix for ambiguous nt in intarna output
    system "sed -i '/contains ambiguous IUPAC nucleotide encodings/d' Cop_IntaRNA1_ui.intarna";

    system $PATH_COPRA_SUBSCRIPTS . "prepare_output_for_websrv_new.pl CopraRNA_result.csv Cop_IntaRNA1_ui.intarna";
    system "mv coprarna_internal_table.csv coprarna_websrv_table.csv";

    system "cp $orgofintTargets target_sequences_orgofint.fa";
}

system $PATH_COPRA_SUBSCRIPTS . "print_archive_README.pl > README.txt";

if ($enrich) { 

    ##### create DAVID enrichment table
    ## this has all been changed to python in version 2.0.3.1 because the DAVID-WS perl client was flawed
    system $PATH_COPRA_SUBSCRIPTS . "DAVIDWebService_CopraRNA.py CopraRNA_result_all.csv $enrich > DAVID_enrichment_temp.txt"; 
    system "grep -P 'termName\\s=|categoryName\\s=|score\\s=|listHits\\s=|percent\\s=|ease\\s=|geneIds\\s=|listTotals\\s=|popHits\\s=|popTotals\\s=|foldEnrichment\\s=|bonferroni\\s=|benjamini\\s=|afdr\\s=' DAVID_enrichment_temp.txt | sed 's/^[ ]*//g' | sed 's/ = /=/g' | sed 's/, /,/g' > DAVID_enrichment_grepped_temp.txt"; ##  only removing obsolete spaces and keeping others
    system $PATH_COPRA_SUBSCRIPTS . "make_enrichment_table_from_py_output.pl DAVID_enrichment_grepped_temp.txt > termClusterReport.txt"; 

    open(MYDATA, "termClusterReport.txt") or system "echo 'If you are reading this, then your prediction did not return an enrichment, your organism of interest is not in the DAVID database\nor the DAVID webservice is/was termporarily down. You can either rerun your CopraRNA\nprediction or create your enrichment manually at the DAVID homepage.' > termClusterReport.txt";
        my @enrichment_lines = <MYDATA>;
    close MYDATA;

    unless($enrichment_lines[0]) {
        system "echo -e 'If you are reading this, then your prediction did not return an enrichment, your organism of interest is not in the DAVID database\nor the DAVID webservice is/was termporarily down. You can either rerun your CopraRNA\nprediction or create your enrichment manually at the DAVID homepage.' > termClusterReport.txt";
    }

    ##### end DAVID enrichment

    ## enrichment visualization
    system "cp $PATH_COPRA_SUBSCRIPTS" . "copra_heatmap.html ."; 
    system "R --slave -f " . $PATH_COPRA_SUBSCRIPTS . "extract_functional_enriched.R --args CopraRNA_result_all.csv termClusterReport.txt enrichment.txt";
    system $PATH_COPRA_SUBSCRIPTS . "make_heatmap_json.pl enrichment.txt"; 
    system "cp $PATH_COPRA_SUBSCRIPTS" . "index-thumb.html ."; 
    system "cp $PATH_COPRA_SUBSCRIPTS" . "index-pdf.html ."; 
    system "phantomjs " . $PATH_COPRA_SUBSCRIPTS . "rasterize.js " . "./index-thumb.html enriched_heatmap_big.png"; 
    system "phantomjs " . $PATH_COPRA_SUBSCRIPTS . "rasterize.js " . "./index-pdf.html enriched_heatmap_big.pdf"; 
    system "rm index-thumb.html"; 
    system "rm index-pdf.html"; 
    ## end add enrichment vis
}


close ERRORLOG;

