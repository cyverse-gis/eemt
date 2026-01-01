import os
import sys 
import re 
from math import pow, floor
from subprocess import Popen, PIPE
class Tiff:
##--DAYMET Default Data
    DAYMET_proj="+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"
    stLat=50
    stLon=-132
    stTile=12625
##--PRISM Default Data
    PRISM_proj=""
    def __init__(self, path,filename, outputdir):
        self.projdir=outputdir
        self.filename=filename
        self.location=path
        self.filepath=os.path.join(self.location,self.filename)
        self.nPixelX=0
        self.nPixelY=0
        self.projCoords=list()
        self.deciCoords=list()
        self.DAYMET_tile=list()
        self.loadTiff()
        self.calculateDAYMETTile()
        self.calculateRegion()
    def loadTiff(self):
        if not os.path.isfile(self.filepath):
            sys.exit("File does not exist, or permissions are incorrect")
        cmdInfo = ['gdalinfo', self.filepath]
        
        # Regular expressions for upper left coords extraction
        ulCoords = re.compile(r"""Upper\s+Left\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,
                             \s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        
        # Regular expressions for lower right coords extraction
        lrCoords = re.compile(r"""Lower\s+Right\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,
                             \s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        # Execute the command
        process = Popen(cmdInfo, stdout=PIPE, shell=False)
        output, err = process.communicate()
         
        if process.returncode != 0:
            raise RuntimeError("%r failed, status code %s stdout %r stderr %r" % \
                                (cmdInfo, process.returncode, output, err))
        
        # Process gdalinfo output by lines
        output = output.split('\n')
        for i in xrange(len(output) - 1, -1, -1):
            if output[i].startswith("Size is"):
                # Extract # of pixels along X,Y axis
                self.nPixelX = int(output[i].split(' ')[2][:-1])
                self.nPixelY = int(output[i].split(' ')[3])
                break

            match = lrCoords.search(output[i])
            if match:
                self.projCoords.append((match.group(1), match.group(2)))
                lat = 0.0
                lon = 0.0
                # caculate latitude and longitude in decimal degrees
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
                
                # upper left coordinate is three lines above
                match = ulCoords.search(output[i-3])
                self.projCoords.append((match.group(1), match.group(2)))
                lat = 0.0
                lon = 0.0
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
    def calculateDAYMETTile(self):
    ##--Tiff Data
        ulLat=self.deciCoords[1][0]
        ulLon=self.deciCoords[1][1]
        lrLat=self.deciCoords[0][0]
        lrLon=self.deciCoords[0][1]
    ##--Calculations
        ulLat = self.stLat + floor((ulLat - self.stLat) / 2) * 2
        ulLon = self.stLon + floor((ulLon - self.stLon) / 2) * 2
        lrLat = self.stLat + floor((lrLat - self.stLat) / 2) * 2
        lrLon = self.stLon + floor((lrLon - self.stLon) / 2) * 2
        
        ulTile = int(self.stTile + ((ulLat - self.stLat) / 2) * 180 + (ulLon - self.stLon) / 2)
        self.DAYMET_tile.append(ulTile)
        lrTile = int(self.stTile + ((lrLat - self.stLat) / 2) * 180 + (lrLon - self.stLon) / 2)
        self.DAYMET_tile.append(lrTile)
####################################
        for i in range(int((ulLat-lrLat) / 2) +1):
            for j in range(int((lrLon-ulLon) / 2) +1):
                tarTile = ulTile - i * 180 + j
                #print tarTile
############################3     
    def calculateRegion(self):
        command = ['gdalinfo', self.filepath]
        process=Popen(command, stdout=PIPE, shell=False)
        stdout,stderr=process.communicate()
        if process.returncode != 0:
            print stderr
            sys.exit("Could not open " + self.filename)
        stdout = stdout.split('\n')
        self.region=""
        for line in stdout:
            if line.startswith('    AUTHORITY'):
                line=line.translate(None, '[]"/')
                line = line.split(',')
                self.region=line[1]
        if not self.region:
            print("ERROR: Could not calculate region of Tif")
            quit(1)
    def mergeTiff(self,other,path,output):
        for tif in other:
            if not os.path.isfile(tif.filepath):
                sys.exit("File " + tif + " does not exist")
        if not os.path.exists(os.path.join(path,output)):
        ##--Generate Command
            command = ['gdalwarp','-overwrite']
            command.append(self.filepath)
            for tif in other:
                command.append(tif.filepath)
            command.append(os.path.join(path,output))
        ##--Execute
            process = Popen(command, stdout=PIPE, shell=False)
            stderr=process.communicate()
            if process.returncode != 0:
                print stderr
            else:
                print("Finished merging " + output)
            new_tiff=Tiff(path,output,"")
            return new_tiff
        else:
            print("File " + output + " already exists. Exiting")      
    def warp(self,proj):
        if proj=="DAYMET":
            print("Converting to DAYMET Projection")
            t_proj=self.DAYMET_proj
        elif proj=="PRISM":
            print("Converting to PRISM Projection")
            t_proj=self.PRISM_proj
        else:
            raise RuntimeError("Invalid projection type")
        # I have removed the , '-tr', '10', '-10' from the end of the statement. 
        command = ['gdalwarp', '-s_srs', 'EPSG:' + self.region, '-overwrite', '-t_srs',t_proj, '-r', 'bilinear', '-of', 'GTiff']
        output_file=self.filename[:-4]+"_converted.tif"
        output_file=os.path.join(self.projdir,output_file)
        command.append(self.filename)
        command.append(output_file)
        process = Popen(command,stdout=PIPE,shell=False)
        stderr=process.communicate()
        if process.returncode != 0:
            sys.exit(stderr)
        return output_file
def createMultiBandTiff():
    print("CreateMultiBandTiff")
    return
