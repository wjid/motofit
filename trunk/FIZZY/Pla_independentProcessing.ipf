#pragma rtGlobals=1		// Use modern global access method.
#pragma IndependentModule=Ind_Process
//#pragma ModuleName=Ind_Process

// SVN date:    $Date$
// SVN author:  $Author$
// SVN rev.:    $Revision$
// SVN URL:     $HeadURL$
// SVN ID:      $Id$

	static strconstant LOG_PATH = "\\\\Filer\\experiments:platypus:data:FIZ:logs:"
	static StrConstant PATH_TO_PLATYPUS = "\\\\Filer\\experiments:platypus:"
	static constant BUFSIZE = 8192
	static Strconstant DASserverIP = "137.157.202.140"
	static Constant DASserverPort = 8080
	
static function parseReply(msg,lhs,rhs)
	string msg
	string &lhs,&rhs
	lhs = ""
	rhs = ""
	msg=replacestring(" = ",msg, "=")
	msg = removeending(msg, "\n")
	variable items = itemsinlist(msg,"=")
	if(items==2)
		lhs = replacestring(" ", stringfromlist(0,msg, "="),"")
		rhs = stringfromlist(1,msg, "=")
	endif
	return items
end

static Function INDstatemonclear(item)
	string item
	Wave/t statemon = root:packages:platypus:SICS:statemon
	for(;;)
		findvalue/TEXT=item/TXOP=4 statemon
		if(V_Value == -1)
			break
		else
			deletepoints V_Value, 1, statemon
		endif
	endfor
End

Function/t removeAllChars(str, char)
	string str, char
	string retStr = ""
	variable pos, lastpos = 0
	
	if(strlen(str) == 0)
		return retStr
	endif
	do
		pos = strsearch(str, char, lastpos)
		if(pos == -1)
			retstr += str[lastpos, strlen(str)]
		else
			retStr += str[lastpos, pos-1]
		endif
		lastpos = pos+1
	while(strsearch(str, char, lastpos) > -1)
	return retStr
End

Function cmdProcessor(w,x)
	Wave/t w
	variable x

	w[x][0] = removeAllChars(w[x][0], num2char(0))
	if(itemsinlist(winlist("sicscmdpanel",";","")))
		notebook sicscmdpanel#NB0_tab0, selection = {endoffile,endoffile}, textRGB = (0,0,0),fstyle=0
		notebook sicscmdpanel#NB0_tab0, selection={endoffile,endoffile}, text="\t"+w[x][0]+"\r"
	endif
End

Function interestProcessor(w,x)
	Wave/t w
	variable x
	//used as a sockit for the SICS_interest channel
	NVAR SOCK_interest = root:packages:platypus:SICS:SOCK_interest
	
	//current status of SICS
	SVAR sicsstatus = root:packages:platypus:SICS:sicsstatus
	
	//the SICS statemonitor
	Wave/t statemon = root:packages:platypus:SICS:statemon

	//current datafilename
	SVAR samplename = root:packages:platypus:SICS:sampleStr
	
	//for streameddetector
	NVAR/z EOSfileID = root:packages:platypus:data:RAW:EOSfileID
	NVAR/z endoflastevent = root:packages:platypus:data:RAW:endoflastevent
	Wave/z streamedDetector = root:packages:platypus:data:RAW:streamedDetector
	Wave/z tbins = root:packages:platypus:data:RAW:tbins
	Wave/z ybins = root:packages:platypus:data:RAW:ybins
	Wave/z xbins = root:packages:platypus:data:RAW:xbins

	variable num,col,row,items,pos, temp
	string str,str1,str2
	Struct WMBackgroundStruct s
	
	//list of all the hipadaba paths and their values
	Wave/t hipadaba_paths = root:packages:platypus:SICS:hipadaba_paths
	
	w[x][0] = removeAllChars(w[x][0], num2char(0))
	
	//first see if it's a position that has changed?
	//the list of current motor positions is kept in axeslist
	//have to change the axeslist colour if the motor is moving.  THis is done by changing the value of the background col plane in selaxeslist
	Wave/t axeslist = root:packages:platypus:SICS:axeslist
	Wave selaxeslist = root:packages:platypus:sics:selAxesList
	items = parseReply(w[x][0],str1, str2)
	//	print x, "                ", w[x][0]
	//this code should parse upper and lower limit changes, as well as position changes.
	if(items==2)
		strswitch(str1)//see what the message is about
			case "STARTED":		//this is listening to the statemon starting an axis
				if(stringmatch(str2, "histmem"))
					break
				endif
				
				redimension/n=(numpnts(statemon)+1) statemon
				statemon[numpnts(statemon) - 1] = str2
				
				//if its a motor axis we want to change the colour in the panel.
				Findvalue/Text=str2/TXOP=4 axeslist
				if(v_value !=-1)
					col = floor(v_value/dimsize(axeslist,0))
					row = v_value-col*dimsize(axeslist,0)
					if(col==1 || col==0)
						selaxeslist[row][][1] = 1
					endif
				endif
				if(stringmatch(str2, "hmcontrol") || stringmatch(str2, "HistogramMemory"))
					startStreamingImage()
				endif
				break
			case "FINISH":		//this is listening to the statemon finishing an axis
				INDstatemonclear(str2)
				
				//if its an motor axis we want to change the colour in the axeslist
				Findvalue/Text=str2/TXOP=4 axeslist
				if(v_value !=-1)
					col = floor(v_value/dimsize(axeslist,0))
					row = v_value-col*dimsize(axeslist,0)
					if(col==1 || col==0)
						selaxeslist[row][][1] = 0
					endif
				endif
				if(stringmatch(str2, "hmcontrol") || stringmatch(str2, "HistogramMemory"))
					temp = endoflastevent 
					if(sum(streameddetector) != str2num(str2))
						nunpack_intodet(EOSfileID, temp, streamedDetector, tbins, ybins, xbins)
						endoflastevent = temp
					endif
					stopStreamingImage()
				endif
				
				//cause any scans to see if they need updating
				//				execute/P/Q "DoXOPIdle"
				//				execute/P/Q "ProcGlobal#Platypus#forceScanBkgTask()"
				//				execute/P/Q "DoXOPIdle"
				//				execute/P/Q "ProcGlobal#forcebatchbkgtask()"
				//				execute/P/Q "DoXOPIdle"
								
				break
			case "status":
				sicsstatus = str2
				if(stringmatch(str2, "Eager to execute commands"))
					SetVariable/Z sicsstatus win=instrumentlayout, valueBackColor=(0,65280,0)
					SetVariable/Z sicsstatus_tab0 win=SICScmdPanel, valueBackColor=(0,65280,0)
				else
					SetVariable/Z sicsstatus win=instrumentlayout, valueBackColor=(65280,0,0)
					SetVariable/Z sicsstatus_tab0 win=SICScmdPanel, valueBackColor=(65280,0,0)
				endif
				
				//if(stringmatch(str2, "Eager to execute commands"))
					//cause any scans to see if they need updating
					//					execute/P/Q "DoXOPIdle"
					//execute/Q "ProcGlobal#Platypus#forceScanBkgTask()"
					//execute/P/Q "DoXOPIdle"
					//					execute/P/Q "ProcGlobal#forcebatchbkgtask()"
					//					execute/P/Q "DoXOPIdle"
				//endif
								
				break
			case "/commands/scan/runscan/feedback/status":
				if(stringmatch(str2, "IDLE"))
					SetVariable/Z runscanstatus win=instrumentlayout, valueBackColor=(0,65280,0)
				else
					SetVariable/Z runscanstatus win=instrumentlayout, valueBackColor=(65280,0,0)
				endif
				
				break
			case "/sample/name":
				sampleName = str2
				break
			case "/instrument/detector/total_counts":
				temp = endoflastevent 			
				if(sum(streameddetector) != str2num(str2))
					nunpack_intodet(EOSfileID, temp, streamedDetector, tbins, ybins, xbins)
					endoflastevent = temp
				endif
				break
			default:
				Findvalue/Text=str1/TXOP=4 axeslist
				if(v_value !=-1)
					col = floor(v_value/dimsize(axeslist,0))
					row = v_value-col*dimsize(axeslist,0)
					if(col==1 || col==0)
						axeslist[row][2] = num2str(str2num(str2))				 
						//				beep
					endif
		
					if(col==3 || col ==5)
						axeslist[row][col+1] = num2str(str2num(str2))
						//if the softlimits have changed, need to update positions, as a notify isn't always sent.
						//send on the interest channel.  SHould just be able to send the short axis name
						//this will make this processor function slightly recursive
						sockitsendmsg/time=1 sock_interest, axeslist[row][0] + "\n"
						sockitsendmsg/time=1 sock_interest, "hget " + axeslist[row][1] + "\n"
					endif
				endif
				break
		endswitch
		
		//search for it in the hipadaba_paths
		findvalue/text=str1/txop=4/z hipadaba_paths
		if(v_value != -1)
			col = floor(v_value/dimsize(hipadaba_paths,0))
			row = v_value-col*dimsize(hipadaba_paths,0)
			if(col==0)
				hipadaba_paths[row][1] = str2
			endif
			Ind_Process#log_msg(str1 + "\t" + str2)
		endif
	endif
End

Function log_close()
	NVAR/z logID = root:packages:platypus:SICS:logID
	fstatus logID
	if(V_flag)
		close logID
	endif
ENd

Threadsafe Function log_msg(msg)
	string msg
	NVAR/z logID = root:packages:platypus:SICS:logID

	string fname, msg2

	if(!NVAR_exists(logID))
		variable/g root:packages:platypus:SICS:logID = 0
		NVAR/z logID = root:packages:platypus:SICS:logID
	endif
	fstatus logID
	if(!V_flag || (V_Flag && V_logEOF> 52800000))
		if (V_Flag && V_logEOF> 52800000)
			close logID
			logID = 0
		endif
		fname = "FIZlog"+Secs2Date(DateTime,-2,"-")
		fname += "T" + replacestring(":", Secs2Time(DateTime,3), "")
		open logID as log_path + fname
		print "opened FIZlog as", log_path+fname, logID
	endif
	msg2 = num2istr(datetime) + "\t" + msg + "\n"
	fbinwrite logID, msg2
End

Function processBMON3rate(w,x)
	Wave/t w
	variable x
	//a SOCKIT processor function for the messages coming back from the open TCPIP connection to beam monitor 3.
	//the whole point of this is to make sure that the detector isn't overwhelmed.
	//	NVAR SOCK_interupt = root:packages:platypus:SICS:SOCK_interupt
	//	NVAR SOCK_interest = root:packages:platypus:SICS:SOCK_interest
		
	NVAR bmon3_rate = root:packages:platypus:SICS:bmon3_rate
	NVAR bmon3_counts = root:packages:platypus:SICS:bmon3_counts
	string rateStr
	
	if(strsearch(w[x][0], num2char(0), 0) > -1 )
		print "GOT THE NULL", w[x][0]
		w[x][0] = replacestring(num2char(0), w[x][0], "")
	endif

	
	rateStr = w[x][0]
	variable val0,val1,val2,val3,val4,val5,val6,val7,val8,val9
	sscanf rateStr,"%d:%d:%g ( %g), %d (%d),%g ( %g, %g, %g)" , val0,val1,val2,val3,val4,val5,val6,val7,val8,val9
	bmon3_rate = round(val6)

	//	if(bmon3_rate > 20000 &&  val4 >= bmon3_counts)
	//		sockitsendmsg sock_interupt,"INT1712 3\n"
	//		doxopidle
	//		sleep/t 20
	//		sockitsendmsg SOCK_interest,"bat send oscd=0\n"
	//		sockitsendmsg SOCK_interest,"run ss1vg 0\nrun ss2vg 0\nrun ss3vg 0\nrun ss4vg 0\n"
	//		sockitsendmsg SOCK_interest,"run bz 250\n"
	//		print "DETECTOR RATE IS TOO HIGH, CLOSING SLITS, inserting ATTENUATOR (processBMON3rate)"
	//	endif
	bmon3_counts = val4
	return 0
End

Threadsafe Function DetectorSentinel()
	variable sock_sics, sock_bmon3, ii
	variable val0,val1,val2,val3,val4,val5,val6,val7,val8,val9, bmon3_rate, bmon3_counts, lastrate = 0
	string msg,temp
	
	sock_sics=sockitopenconnectionF("137.157.202.139",60003,10)
	sock_bmon3=sockitopenconnectionF("137.157.202.140",30002,10)
	
	if(sockitisitopen(sock_sics)==-1 || sockitisitopen(sock_bmon3)==-1)
		print "ERROR couldn't open sentinel sockets"
	endif
	
	sockitsendmsgF(sock_SICS,"manager ansto\n")
	sockitsendmsgF(sock_bmon3,"REPORT ON\n")
	bmon3_counts = 0
	print "Detector Sentinel started"
	
	do
		temp = SOCKITPeek(sock_sics)
		msg = SOCKITpeek(sock_bmon3)
		for(ii=0 ; ii<itemsinlist(msg, "\n") ; ii+=1)
			sscanf stringfromlist(ii, msg, "\n"), "%d:%d:%g ( %g), %d (%d),%g ( %g, %g, %g)" , val0,val1,val2,val3,val4,val5,val6,val7,val8,val9
			bmon3_rate = val6
			//			print bmon3_rate, val4, bmon3_counts
			if((bmon3_rate > 12000 && lastrate > 12000))
				sockitsendmsgF(sock_sics,"INT1712 3\n")
				temp = ThreadGroupGetDF(0, 200 )
				sockitsendmsgf(sock_sics,"bat send oscd=0\ndrive ss1vg 0 ss2vg 0 ss3vg 0 ss4vg 0 bz 250\n")
				log_msg("COUNTRATETOOHIGH")
				print "DETECTOR RATE IS TOO HIGH, CLOSING SLITS, inserting ATTENUATOR (DetectorSentinel)"
				temp = ThreadGroupGetDF(0, 5000 )
			endif
			lastrate = bmon3_rate
			bmon3_counts = val4
		endfor
		temp = ThreadGroupGetDF(0, 1000 )
		
		if(sockitisitopen(sock_sics)==-1)
			sock_sics=sockitopenconnectionF("137.157.202.139",60003,10)
			if(sock_sics==-1)
				print "ERROR sentinel socket closed"
				return 1
			endif
		endif
		if(sockitisitopen(sock_bmon3)==-1)
			sock_bmon3=sockitopenconnectionF("137.157.202.140",30002,10)
			if(sock_bmon3==-1)
				print "ERROR sentinel socket closed"
				return 1
			endif
		endif
	while(1)

	sockitcloseconnection(sock_SICS)
	sockitcloseconnection(sock_bmon3)
	return 0
End

Function/t grabHistoStatus(keyvalue)
	string keyvalue
	//this function returns the status of the Histogram server from it's text status
	string retStr,cmd

	sprintf cmd,"http://%s:%d/admin/textstatus.egi",DASserverIP,DASserverport
	easyHttp/PROX=""/PASS="manager:ansto" cmd

	if(V_Flag)
		Print "Error while speaking to Histogram Server (grabHistoStatus)"
		return ""
	endif
	retStr = S_getHttp
	retStr = replacestring("\n",retStr,"\r")
	retstr = stringbykey(keyvalue,retStr,":","\r")
	if(!cmpstr(retstr[0]," "))
		retstr = retstr[1,inf]		
	endif
	return retstr
End


Function startStreamingImage()
	//setup the datafolders
	DFREF saveDFR = GetDataFolderDFR()
	
	Newdatafolder/o root:packages
	Newdatafolder/o root:packages:platypus
	Newdatafolder/o root:packages:platypus:data
	newdatafolder/o/s root:packages:platypus:data:RAW
		
	//get the daq filename
	string/g DAQdirectory = grabHistoStatus("DAQ_dirname")
	variable/g datanumber = str2num(grabHistoStatus("DATASET_number"))
	string/g EOSfileStr = PATH_TO_PLATYPUS + "hsdata:" + DAQdirectory + ":DATASET_" + num2istr(datanumber) + ":EOS.bin"
	//grab the config file for the bins.
	NVAR/z EOSfileID, endoflastevent
	if(NVAR_exists(EOSfileID))
		if(EOSfileID)
			close EOSfileID
			EOSfileID = 0
		endif
	else
		variable/g EOSfileID = 0	
		variable/g endoflastevent
	endif
	endoflastevent = 127

	variable cfgfileID = xmlopenfile(PATH_TO_PLATYPUS + "hsdata:" + DAQdirectory + ":CFG.xml")
	if(cfgfileID < 1)
//		print "ERROR, could not find config file, cannot update streamed detector image"
		setdatafolder saveDFR
		return 1
	endif
	//get the bin settings
	xmlwavefmxpath(cfgfileID, "//OAT/X/X", "", " \n")
	Wave/t M_xmlcontent
	make/n=(dimsize(M_xmlcontent, 0) - 1)/d/o xbins
	xbins[] = str2num(M_xmlcontent[p])
	xmlwavefmxpath(cfgfileID, "//OAT/Y/Y", "", " \n")
	Wave/t M_xmlcontent
	make/n=(dimsize(M_xmlcontent, 0) - 1)/o/d ybins
	ybins[] = str2num(M_xmlcontent[p])
	xmlwavefmxpath(cfgfileID, "//OAT/T/T", "", " \n")
	Wave/t M_xmlcontent
	make/n=(dimsize(M_xmlcontent, 0) - 1)/o/d tbins
	tbins[] = str2num(M_xmlcontent[p])
	killwaves/z M_xmlcontent, W_xmlcontentnodes
	xmlclosefile(cfgfileID, 0)
	//create a detector image
	Wave/z hmm = root:packages:platypus:data:RAW:streamedDetector
	if(!waveexists(hmm))
		make/n=(numpnts(tbins) - 1, numpnts(ybins) - 1, numpnts(xbins) - 1)/o/u/i streamedDetector = 0
	else
		redimension/u/i/n=(numpnts(tbins) - 1, numpnts(ybins) - 1, numpnts(xbins) - 1) hmm
		hmm = 0
	endif
	//open the streamed file
	open/r/z EOSfileID as EOSfileStr
	if(V_flag)
//		print "ERROR, could not find EOS.bin file, cannot update streamed detector image"
		setdatafolder saveDFR
		EOSfileID = 0
		return 1
	endif	
	setdatafolder saveDFR
End

Function stopstreamingimage()
	NVAR/z EOSfileID = root:packages:platypus:data:RAW:EOSfileID
	if(NVAR_exists(EOSfileID) && EOSfileID)
		close EOSfileID
		EOSfileID = 0
	endif
End

Function nunpack_intodet(fileID, endoflastevent, detector, tbins, ybins, xbins)
	variable fileID, &endoflastevent
	wave detector, tbins, ybins, xbins

	variable state = 0, event_ended = 0, frame_number = -1;
	variable x, y;
	variable dt, t = 0;
	variable c
	variable filePos, currentbuffersize, ii, entries, processedEvents, finish

	variable xpos, ypos, tpos, numxbins, numybins, numtbins
	
	if(!fileID)
		return 0
	endif
	
	numxbins = dimsize(xbins, 0) - 1
	numybins = dimsize(ybins, 0) - 1
	numtbins = dimsize(tbins, 0) - 1
	
	make/n=(BUFSIZE)/free/u/b buffer
	finish = 0
	currentbuffersize = BUFSIZE
	for(;!finish;)
		fstatus fileID
		if(endoflastevent + 1 != V_logEOF && endoflastevent < V_logEOF)
			fsetpos fileID, endoflastevent + 1
		else
			break
		endif	
		filePos = endoflastevent + 1
		if(V_logEOF - filepos < BUFSIZE)
			redimension/n=(V_logEOF - filepos) buffer
			currentbuffersize = V_logEOF - filepos
			finish = 1
		elseif(currentbuffersize != BUFSIZE)
			redimension/n=(BUFSIZE) buffer
			currentbuffersize = BUFSIZE
		endif
		fbinread/u/f=1 fileID, buffer
		state = 0
		
		for(ii = 0 ; ii < currentbuffersize ; ii += 1)
			c = buffer[ii]
			switch(state)
				case 0:
					x = c;
					state += 1;
					break;
				case 1:
					x = x | ((c & 0x3) * 256)
					if (x & 0x200)
						x = -(2^32 - ( x | 0xFFFFFC00))
					endif
					y= c / 4;
					state += 1
					break;
				case 2:
					y = y | ((c & 0xF) * 64)
					if (y & 0x200)
						y = -(2^32 - ( y | 0xFFFFFC00));
					endif
				case 3:
				case 4:
				case 5:
				case 6:
				case 7:	
					event_ended = (state >= 7 || (c & 0xC0) != 0xC0)

					if (!event_ended)
						c = c & 0x3F;
					endif
					if (state == 2)
						dt= c / 16;
					else
						dt = dt | (c * (2^(2 + 6 * (state - 3))))
					endif
					if (!event_ended)
						state += 1;
					else
						state=0;
						endoflastevent = filepos + ii
						if (x == 0 && y == 0 && dt == 0xFFFFFFFF)
							t = 0;
							frame_number += 1;
						else	
							t += dt;
							if(frame_number == -1)
								return 1;
							endif
		
							xpos = binarysearch(xbins, x)
							ypos = binarysearch(ybins, y)
							tpos = binarysearch(tbins, t/1000)
							if(xpos < 0 || ypos < 0 || tpos < 0)
								continue
							endif

							if(xpos == numxbins )
								xpos -= 1
							endif
							if(ypos == numybins )
								ypos -= 1
							endif
							if(tpos == numtbins )
								tpos -= 1
							endif
							detector[tpos][ypos][xpos] += 1
						endif
					endif
					break
			endswitch	
		endfor

	endfor
	return endoflastevent
End