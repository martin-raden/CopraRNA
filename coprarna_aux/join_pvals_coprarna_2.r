# script by Jens Georg

#call:
#R --slave -f /home/jens/CopraRNA-git/coprarna_aux/join_pvals_coprarna_2.r --args ooi_only=FALSE prediction_on_subset=TRUE	outlier_removal=TRUE maxorgs=15	 
 
#Dependencies:
suppressPackageStartupMessages(require(phangorn))
suppressPackageStartupMessages(require(seqinr))
suppressPackageStartupMessages(require(doMC))


# read the organism of interest (ooi) from the ncRNA fasta file. The sRNA of the ooi is considered to be the first sequence.
ooi<-gsub("ncRNA_","",names(read.fasta("ncrna.fa"))[1])

order_method="phylogenetic"		# options = p_value or phylogenetic
name="result_all"
mnum=40000
weight_method<-"clustal"		# organism weights caluclated by the CopraRNA1 method (copra) or the ClustalW method (clustal)
weight_tree<-"upgma"			# "ML" , "upgma"
outlier_removal=FALSE			# Should p-value outliers be removed prior to p-value combination
rholimit<-TRUE					# if TRUE rho can take only values between  0 and 1 even if the fit suggests higher rho values
rho_weights<-1					# Controls if the fit for the dependency in the data should run on all data (rho_weights=1) or on the 1/x lowest p-Values (rho_weights=x).
min_length<-2					# minimal number of homologs for combining a p_value
ooi_only=FALSE					# prediction for all included organisms or only the ooi
prediction_on_subset=FALSE		# Should the p-value combination be done on all organisms or on an optimized subsets. Only if ooi_only=FALSE. Requires to calculate the optimized subsets. 
# For organisms subset selection
mindis=0						# minimal required distance to the respective ooi
maxorgs=15						# number of selected organisms, if possible
maxdis=0.5						# maximal allowed distance to the ooi to be considered

# register cores for parallel processing
co<-readLines("CopraRNA_option_file.txt") 
max_cores<-as.numeric(gsub("core count:","",co[grep("core count:", co)]))

root<-as.numeric(gsub("root:","",co[grep("root:", co)]))


# get absolute path
initial.options <- commandArgs(trailingOnly = FALSE)
path<-initial.options [4]
path<-sub("join_pvals_coprarna_2.r","",path)


# transforming arguments into valid variables 
args <- commandArgs(trailingOnly = TRUE) 
if(length(args)>0){
	for(i in 1:length(args)){
		temp<-strsplit(args[i],"=")
		temp<-temp[[1]]
		temp1<-temp[1]
		temp2<-temp[2]
		assign(as.character(temp1),temp2)
	}
}

rholimit<-as.logical(rholimit)
rho_weights<-as.numeric(rho_weights)
mnum<-as.numeric(mnum)
min_length<-as.numeric(min_length)
prediction_on_subset<-as.logical(prediction_on_subset)
ooi_only<-as.logical(ooi_only)
outlier_removal<-as.logical(outlier_removal)
mindis<-as.numeric(mindis)
maxorgs<-as.numeric(maxorgs)
maxdis<-as.numeric(maxdis)
max_cores<-as.numeric(max_cores)
registerDoMC(max_cores)
root<-as.numeric(root)

if(ooi_only==T){
	prediction_on_subset<-FALSE
}

if(prediction_on_subset==T){
	system(paste("R --slave -f ", path, "coprarna_selection_fast.r --args mindis=",mindis," maxorgs=",maxorgs, " maxdis=",maxdis, sep=""))
	load("orgs_selection.Rdata") 
}

tree_weights<-function(tree, method="clustal"){
	tip<-Ntip(tree)
	node<-Nnode(tree)
	di<-dist.nodes(tree)
	root<-setdiff(tree[[1]][,1],tree[[1]][,2])
	out<-vector("list",tip)
	names(out)<-1:tip
	for(i in 1:tip){
		temp<-numeric(0)
		t1<-i
		while(t1!=(tip+1)){
			t1<-tree[[1]][which(tree[[1]][,2]==t1),1]
			temp<-c(temp,t1)
		}
		out[[i]]<-temp
	}
	count<-table(unlist(out))
	le<-0
	for(i in 1:length(count)){
		t1<-tree[[1]][which(tree[[1]][,2]==as.numeric(names(count)[i])),1]
		le<-c(le,di[t1,as.numeric(names(count)[i])])
	}
	if(method=="clustal"){
		count<-le/count
	}
	if(method=="copra"){
		names(le)<-names(count)
		count<-le/2
		
	}
	weight<-numeric()
	for(i in 1:tip){
		t1<-di[as.numeric(names(out)[i]),out[[i]][1]]
		po<-match(out[[i]],names(count))
		weight<-c(weight,sum(count[po],t1))
		
	}
	names(weight)<-tree$tip.label
	weight<-weight/sum(weight)
	weight
}

mafft<-function(filename="ncrna.fa", outname="ncrna_aligned.fa", mode="fast"){
	if(mode=="accurate"){
		command<-paste("mafft --maxiterate 1000 --localpair --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	if(mode=="fast"){
		command<-paste("mafft --retree 2 --maxiterate 0 --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	if(mode=="very_fast"){
		command<-paste("mafft --retree 1 --maxiterate 0 --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	system(command)
} 

if(weight_tree=="ML"){
	mafft("16s_sequences.fa", outname="16s_sequences_mafft_align.fas", mode="accurate")
	ribo<-read.phyDat("16s_sequences_mafft_align.fas", format="fasta", type="DNA")
	dm <- dist.ml(ribo, model="F81")
	treeNJ <- NJ(dm)
	mt <- modelTest(ribo, tree=treeNJ, multicore=F)
	bestmodel <- mt$Model[which.min(mt$AICc)]
	env = attr(mt, "env")
	fitStart = eval(get(bestmodel, env), env)
	fit = optim.pml(fitStart, rearrangement = "stochastic",optGamma=TRUE, optInv=TRUE, model="GTR", ratchet.par = list(iter = 50L, maxit = 100L, prop = 1/3))
	weight<-tree_weights(midpoint(fit$tree), method=weight_method)
}

if(weight_tree=="NJ"){
	mafft("16s_sequences.fa", outname="16s_sequences_mafft_align.fas", mode="accurate")
	ribo<-read.phyDat("16s_sequences_mafft_align.fas", format="fasta", type="DNA")
	dm <- dist.ml(ribo, model="F81")
	treeNJ <- NJ(dm)
	weight<-tree_weights(midpoint(treeNJ), method=weight_method)
}

if(weight_tree=="upgma"){
	mafft("16s_sequences.fa", outname="16s_sequences_mafft_align.fas", mode="accurate")
	ribo<-read.phyDat("16s_sequences_mafft_align.fas", format="fasta", type="DNA")
	dm <- dist.ml(ribo, model="F81")
	fitJC<- upgma(dm)
	weight<-tree_weights(fitJC, method=weight_method)
}

write.table(weight, file="weights.txt", sep="\t")

#create table of IntaRNA p-Values
myfun<-function(da2){
	int_table<-gsub("^([^\\|]*\\|[^\\|]*\\|)", "",da2)
	int_table<-gsub("\\|.*","",int_table)
	int_table
}
da<-read.csv("CopraRNA2_prep_anno_addhomologs_padj_amountsamp.csv")
en<-grep("Annotation", colnames(da))
da2<-da[,3:(en-1)]
namegenomes<-colnames(da2)
genomes<-list()
int_table<-apply(da2, 2, myfun)
int_table<-matrix(as.numeric(int_table),nrow(int_table),ncol(int_table))
colnames(int_table)<-colnames(da2)
rownames(int_table)<-seq(1,nrow(int_table))

# to transform p-Values into probits
qtrans<-function(dat2){
		if(is(dat2)[1]=="numeric"){
			dat2<-matrix(dat2,1,length(dat2))
		}
        for(i in 1:ncol(dat2)){
                dat2[,i]<-qnorm(dat2[,i], lower.tail=FALSE)
        }
        dat2
}

int_table_all<-int_table
# do prediction for all organisms

if(ooi_only==T){
	namegenomes<-ooi
}

copra_results<-vector("list",length(namegenomes))
names(copra_results)<-namegenomes

for(ii in namegenomes){
	ooi<-ii
	
	if(prediction_on_subset==T){
		selected_genomes<-orgs_selection[[ii]]
	} else {
		selected_genomes<-colnames(da2)
	}
	int_table<-int_table_all[,selected_genomes]
	
	##### exclude ouliers from analysis
	ooi_pos<-grep(ooi, colnames(int_table))
	
	
	if(outlier_removal==TRUE){
		outlier_remove<-function(temp, fa=1.1, ooi_pos){
			med<-median(-log(temp),na.rm=T)
			iqr<-IQR(-log(temp),na.rm=T)
			fa<-1.1
			outlier<-which(-log(temp) >= med+iqr*fa | -log(temp)<= med-iqr*fa)
			ooi_outlier<-which(outlier==ooi_pos)
			if(length(ooi_outlier)>0){
				outlier<-outlier[-ooi_outlier]
			}
			if(length(outlier)>0){
				temp[outlier]<-NA
			}
			temp
		}
	
		int_table<-t(apply(int_table,1,outlier_remove, fa=1.1, ooi_pos=ooi_pos))
	}
	####

	if(order_method=="phylogenetic"){
		load("order_table_all_orgs.Rdata")  
		order_table<-order_table_all_orgs[[ooi]]
		order_table<-order_table[,selected_genomes]
		

		min_length<-min_length
		min_length<-min_length-1
		h<-new.env()
		ooi_pos<-grep(ooi, colnames(order_table))
		ex<-which(is.na(order_table[,ooi_pos])==F)
		for(i in 1:length(ex)){
			temp<-order(as.numeric(order_table[ex[i],]), na.last=NA)
			if(length(temp)>=min_length){
				ma<-length(temp)-min_length
				for(j in 1:ma){
					tmp<-paste(sort(temp[1:j]), collapse="_")
					if(is.null(h[[tmp]])){
						h[[tmp]]<-ex[i]
					} else {
						h[[tmp]]<-c(h[[tmp]],ex[i])
					}
				}
			} 
		}
	}


	if(order_method=="p_value"){
		min_length<-min_length
		min_length<-min_length-1
		h<-new.env()
		ooi_pos<-grep(ooi, colnames(int_table))
		ex<-which(is.na(int_table[,ooi_pos])==F)
		for(i in 1:length(ex)){
			temp<-order(int_table[ex[i],], na.last=NA)
			if(length(temp)>=min_length){  
				mi<-which(temp==1)
				ma<-length(temp)
				for(j in mi:ma){
					tmp<-paste(sort(temp[1:j]), collapse="_")
					if(is.null(h[[tmp]])){
						h[[tmp]]<-ex[i]
					} else {
						h[[tmp]]<-c(h[[tmp]],ex[i])
					}
				}
			}
		}
	}

	

	
	na<-names(h)
	mnum1<-ceiling(length(h)/max_cores)
	spa<-max(floor(length(h)/mnum),floor(length(h)/mnum1))
	mnum<-min(mnum,mnum1)
	rest<-length(h)-(mnum*spa)
	spal<-rep(mnum,spa)
	if(rest>0){
		spa<-spa+1
		spal<-c(spal,rest)
	}
	out2<-rep((list(rep(NA,nrow(int_table)))), spa)
	count_vect1<-cumsum(c(1,spal[1:(length(spal)-1)]))
	count_vect2<-cumsum(spal)

	out<-foreach(jj=1:spa)  %dopar% {
		out<-rep((list(rep(NA,nrow(int_table)))), spal[jj])
		for(i in count_vect1[jj]:count_vect2[jj]){
			temp1<-as.numeric(strsplit(na[i],"_")[[1]])
			temp<-na.omit(int_table[,temp1])
			
					
			wtemp<-weight[match(colnames(int_table)[temp1], names(weight))]
			#wtemp[1]<-max(wtemp)
			if(root==0){
				wtemp<-rep(1,length(wtemp))
			}
			if(root>0 & root!=1){
				wtemp<-wtemp^(1/root)
			}
			position<-h[[na[i]]]
			dat2<-qtrans(temp)
			a<-rowSums(t(t(dat2)*wtemp))
			b<-sum(wtemp)^2
			d<-sum(wtemp^2)
			l<-length(a)
			k<-1/l
			y<-k * seq(1,l)
			dat3<-data.frame(y,a,d,b)
			dat3<-data.frame(y,a)
			w<-rep(0, length(y))
			w[1:(ceiling(length(y))/rho_weights)]<-1
			rhotemp<-tryCatch(
				coef(nls(y~sort(pnorm(a/sqrt((1-rho)*d+rho*b), lower.tail=F)), data=dat3, start=list(rho=0),weights=w,control=list(minFactor = 1/128, tol = 1e-05, warnOnly = TRUE))),
				error=function(e) 
					tryCatch(
						coef(nls(y~sort(pnorm(a/sqrt((1-rho)*d+rho*b), lower.tail=F)), data=dat3, start=list(rho=0.1),weights=w, control=list(minFactor = 1/128, tol = 1e-05, warnOnly = TRUE))),
						error=function(e) 1)
			)
			if(rholimit==TRUE){
				rhotemp<-min(rhotemp,1)
				rhotemp<-max(rhotemp,0)
			}
			out[[(i-count_vect1[jj]+1)]][position]<-pnorm(a[match(as.character(position),rownames(temp))]/sqrt((1-rhotemp)*d+rhotemp*b),lower.tail=F)
			}
		out<-do.call(pmin, c(out,list(na.rm=T)))
		out
	}

	out_evo<-do.call(pmin, c(out,list(na.rm=T)))
	out_fdr<-p.adjust(out_evo, method="BH")
	out_evo<-cbind(out_fdr,out_evo)
	colnames(out_evo)<-c("fdr","p-value")
	an<-da[,3:ncol(da)]
	out_evo<-cbind(out_evo, an)

	initial_sorting<-seq(1,nrow(int_table))
	out_evo<-cbind(out_evo, initial_sorting)
	out_evo<-out_evo[order(as.numeric(out_evo[,2])),]
	out_evo<-as.matrix(out_evo)

	em<-which(out_evo[,ooi]!="")
	p<-lapply(as.character(out_evo[em,ooi]),strsplit,split="\\|")
	p<-lapply(p, unlist)
	p<-do.call("rbind",p)
	IntaRNA_pValue_ooi<-(p[,3])
	out_evo<-cbind(out_evo[,1:2],rep(NA,nrow(out_evo)),out_evo[,3:ncol(out_evo)])
	out_evo[em,3]<-IntaRNA_pValue_ooi
	colnames(out_evo)[3]<-"IntaRNA_pValue_ooi"
	na<-gsub("\\(.*","",out_evo[,ooi])
	dup<-which(duplicated(na))

	if(length(dup)>0){
		na<-na[-dup]
		out_evo<-out_evo[-dup,]
	}
	name2<-paste("CopraRNA_",ooi,".csv",sep="")
	if(ooi_only==T){
		name2<-paste("CopraRNA_",name,".csv",sep="")
	}
	copra_results[[ii]]<-out_evo
	#write.table(out_evo, file=name2,sep=",", quote=F, row.names=F)
}

write.table(copra_results[[1]], file="CopraRNA_result_all.csv",sep=",", quote=F, row.names=F)
save(copra_results, file="copra_results_all.Rdata")


