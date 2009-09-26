#pragma rtGlobals=1		// Use modern global access method.

// SVN date:    $Date$
// SVN author:  $Author$
// SVN rev.:    $Revision$
// SVN URL:     $HeadURL$
// SVN ID:      $Id$


Menu "Platypus"
	"Catalogue data",catalogueNexusdata()
End
	
Function catalogueNexusdata()
	newpath/o/z/q/M="Where are the NeXUS files?" PATH_TO_DATAFILES
	if(V_flag)
		print "ERROR path to data is incorrect (catalogue)"
		return 1
	endif
	pathinfo PATH_TO_DATAFILES
	variable start=1,finish=100000
	prompt start,"start"
	prompt finish,"finish"
	Doprompt "Enter the start and end files",start, finish
	catalogue(S_path,start=start,finish=finish)
	print "file:///"+S_path+"catalogue.xml" 
End

Function catalogue(pathName[, start, finish])
	String pathName
	variable start, finish

	string cDF = getdatafolder(1)
	string nexusfiles,tempStr
	variable temp,ii,jj,HDFref,xmlref, firstfile, lastfile, fnum

	newdatafolder/o root:packages
	newdatafolder/o root:packages:platypus
	newdatafolder/o/s root:packages:platypus:catalogue
	make/o/t/n=(1,7) runlist
	
	if(paramisdefault(start))
		start = 1
	endif

	try
		newpath/o/z/q PATH_TO_DATAFILES, pathname
		if(V_flag)
			print "ERROR path to data is incorrect (catalogue)"
			abort
		endif
	
		nexusfiles = sortlist(indexedfile(PATH_TO_DATAFILES,-1,".hdf"),";",16)
		nexusfiles = replacestring(".nx.hdf", nexusfiles,"")
		nexusfiles = greplist(nexusfiles, "^PLP")
		
		sscanf stringfromlist(0, nexusfiles), "PLP%d", firstfile
		sscanf stringfromlist(itemsinlist(nexusfiles)-1, nexusfiles),"PLP%d",lastfile
		if(paramisdefault(finish))
			finish = lastfile
		endif
		
		pathInfo PATH_TO_DATAFILES
		xmlref = xmlcreatefile(S_path+"catalogue.xml","catalogue","","")
		if(xmlref < 1)
			print "ERROR while creating XML file (catalogue)"
			abort
		endif
		
		jj = 0
		for(ii = 0 ; ii<itemsinlist(nexusfiles) ; ii+=1)
			sscanf stringfromlist(ii, nexusfiles), "PLP%d", fnum
			if(fnum >= firstfile && fnum <= lastfile && fnum >= start && fnum <= finish)
			else
				continue
			endif
			hdf5openfile/p=PATH_TO_DATAFILES/z/r HDFref as stringfromlist(ii,nexusfiles)+".nx.hdf"
			if(V_Flag)
				print "ERROR while opening HDF5 file (catalogue)"
				abort
			endif
		
			appendCataloguedata(HDFref, xmlref, jj, stringfromlist(ii,nexusfiles), runlist)
		
			if(HDFref)
				HDF5closefile(HDFref)
			endif
			jj+=1
		endfor
		setdimlabel 1,0,run_number, runlist
		setdimlabel 1,1,sample, runlist
		setdimlabel 1,2,vslits, runlist
		setdimlabel 1,3,omega, runlist
		setdimlabel 1,4,run_time, runlist
		setdimlabel 1,5,total_counts, runlist
		setdimlabel 1,6,mon1_counts, runlist
		dowindow/k Platypus_run_list
		edit/k=1/N=Platypus_run_list runlist.ld as "Platypus Run List"
	catch
		if(HDFref)
			hdf5closefile/z HDFref
		endif
	endtry

	if(xmlref > 0)
		xmlclosefile(xmlref,1)
	endif

	Killpath/z PATH_TO_DATAFILES

	setdatafolder $cDF
End

Function appendCataloguedata(HDFref,xmlref,fileNum,filename, runlist)
	variable HDFref,xmlref,fileNum
	string filename
	Wave/t runlist
	print fileNum
	
	string tempStr
	variable row,fnum
	if(HDFref<1 || xmlref<1)
		print "ERROR while cataloging, one or more file references incomplete (appendCataloguedata)"
		abort
	endif
	
	//add another row to the runlist
	redimension/n=(fileNum+1,-1) runlist
	row = dimsize(runlist,0)
	
	if(xmladdnode(xmlref,"//catalogue","","nexus","",1))
		abort
	endif
	
	//filename
	if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","file",filename))
		abort
	endif
	sscanf filename, "PLP%d",fnum
	runlist[row][0] = num2istr(fnum)
	
	//runnum, sample name, vslits, omega, time, detcounts, mon1counts
 
	hdf5loaddata/z/q/o hdfref,"/entry1/start_time"
	if(!V_flag)
		Wave/t start_time
		if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","date",start_time[0]))
			abort
		endif
	endif
 
	//user
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","user","",1))
		abort
	endif

	hdf5loaddata/z/q/o hdfref,"/entry1/user/name"
	if(!V_flag)
		Wave/t name
		if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/user","","name",name[0]))
			abort
		endif
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/user/email"
	if(!V_flag)
		Wave/t email
		if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/user","","email",email[0]))
			abort
		endif
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/user/phone"
	if(!V_flag)
		Wave/t phone
		if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/user","","phone",phone[0]))
			abort
		endif
	endif
 
	//experiment
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","experiment","",1))
		abort
	endif
	hdf5loaddata/z/q/o hdfref,"/entry1/experiment/title"
	if(!V_flag)
		Wave/t title
		if(xmlsetattr(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/experiment","","title",title[0]))
			abort
		endif
	endif
	
	//sample
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","sample","",1))
		abort
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/sample/description"
	if(!V_flag)
		Wave/t description
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/sample","","description",description[0],1))
			abort
		endif
	endif

	hdf5loaddata/z/q/o hdfref,"/entry1/sample/name"
	if(!V_flag)
		Wave/t name
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/sample","","name",name[0],1))
			abort
		endif
		runlist[row][1] = name[0]
	endif


	hdf5loaddata/z/q/o hdfref,"/entry1/sample/title"
	if(!V_flag)
		Wave/t title
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/sample","","title",title[0],1))
			abort
		endif
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/sample/sth"
	if(!V_flag)
		Wave sth
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/sample","","sth",num2str(sth[0]),1))
			abort
		endif
	endif
	
	//instrument
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]","","instrument","",1))
		abort
	endif
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument","","slits","",1))
		abort
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/first_horizontal_gap"
	if(!V_flag)
		Wave first_horizontal_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","first_horizontal_gap",num2str(first_horizontal_gap[0]),1))
			abort
		endif
	endif
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/first_vertical_gap"
	if(!V_flag)
		Wave first_vertical_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","first_vertical_gap",num2str(first_horizontal_gap[0]),1))
			abort
		endif
	endif
	 
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/second_horizontal_gap"
	if(!V_flag)
		Wave second_horizontal_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","second_horizontal_gap",num2str(second_horizontal_gap[0]),1))
			abort
		endif
	endif

	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/second_vertical_gap"
	if(!V_flag)
		Wave second_vertical_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","second_vertical_gap",num2str(second_vertical_gap[0]),1))
			abort
		endif
	endif
	 
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/third_horizontal_gap"
	if(!V_flag)
		Wave third_horizontal_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","third_horizontal_gap",num2str(third_horizontal_gap[0]),1))
			abort
		endif
	endif
	
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/third_vertical_gap"
	if(!V_flag)
		Wave third_vertical_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","third_vertical_gap",num2str(third_vertical_gap[0]),1))
			abort
		endif
	endif
 
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/third_vertical_st3vt"
	if(!V_flag)
		Wave third_vertical_st3vt
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","third_vertical_st3vt",num2str(third_vertical_st3vt[0]),1))
			abort
		endif
	endif  
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/fourth_horizontal_gap"
	if(!V_flag)
		Wave fourth_horizontal_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","fourth_horizontal_gap",num2str(fourth_horizontal_gap[0]),1))
			abort
		endif
	endif

	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/fourth_vertical_gap"
	if(!V_flag)
		Wave fourth_vertical_gap
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","fourth_vertical_gap",num2str(fourth_vertical_gap[0]),1))
			abort
		endif
	endif

	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/slits/fourth_vertical_st4vt"
	if(!V_flag)
		Wave fourth_vertical_st4vt
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/slits","","third_vertical_st3vt",num2str(fourth_vertical_st4vt[0]),1))
			abort
		endif
	endif 
	sprintf tempstr,"%0.2f, %0.2f, %0.2f, %0.2f",first_vertical_gap[0], second_vertical_gap[0], third_vertical_gap[0], fourth_vertical_gap[0]
//	tempStr = "("+num2str(first_vertical_gap[0])+","
//	tempStr += num2str(second_vertical_gap[0])+","
//	tempStr += num2str(third_vertical_gap[0])+","
//	tempStr += num2str(fourth_vertical_gap[0])+")"
	runlist[row][2]= tempStr
	
	//parameters
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument","","parameters","",1))
		abort
	endif
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/parameters/mode"
	if(!V_flag)
		Wave/t mode
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/parameters","","mode",mode[0],1))
			abort
		endif
	endif
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/parameters/omega"
	if(!V_flag)
		Wave omega
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/parameters","","omega",num2str(omega[0]),1))
			abort
		endif
		runlist[row][3] = num2str(omega[0])
	endif

	
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/parameters/twotheta"
	if(!V_flag)
		Wave twotheta
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/parameters","","twotheta",num2str(twotheta[0]),1))
			abort
		endif
	endif
 
	//detector
	if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument","","detector","",1))
		abort
	endif
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/detector/longitudinal_translation"
	if(!V_flag)
		Wave longitudinal_translation
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/detector","","longitudinal_translation",num2str(longitudinal_translation[0]),1))
			abort
		endif
	endif

	hdf5loaddata/z/q/o/n=timer hdfref,"/entry1/instrument/detector/time"
	if(!V_flag)
		Wave timer
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/detector","","time",num2str(timer[0]),1))
			abort
		endif
		runlist[row][4] = num2str(timer[0])
	endif
	
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/detector/total_counts"
	if(!V_flag)
		Wave total_counts
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/detector","","total_counts",num2str(total_counts[0]),1))
			abort
		endif
		runlist[row][5] = num2str(total_counts[0])
	endif
	
	hdf5loaddata/z/q/o hdfref,"/entry1/monitor/bm1_counts"
	if(!V_flag)
		Wave bm1_counts
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/detector","","total_counts",num2str(bm1_counts[0]),1))
			abort
		endif
		runlist[row][6] = num2str(bm1_counts[0])
	endif
	 
	hdf5loaddata/z/q/o hdfref,"/entry1/instrument/detector/vertical_translation"
	if(!V_flag)
		Wave vertical_translation
		if(xmladdnode(xmlref,"//catalogue/nexus["+num2istr(filenum+1)+"]/instrument/detector","","vertical_translation",num2str(vertical_translation[0]),1))
			abort
		endif 
	endif
 
End