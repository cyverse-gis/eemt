from subprocess import Popen, PIPE
from math import pow
import os
import re
import sys
import math
import decimal

class TiffParser(object):
    def __init__(self):
        """ Read tiff file info via gdalinfo command."""
        
        # store file name
        self.fileName = ""
        
        # coords list [upleft, lowerleft, upright, lowerright, center]
        self.projCoords = list()
        self.deciCoords = list() 
        
        # number of x and y pixels
        self.nPixelX = 0
        self.nPixelY = 0
        self.proj_info = dict()
        
    def getDecimalCoords(self):
        return self.deciCoords

    def getProjCoords(self):
        return self.projCoords

    def getName(self): 
        return self.fileName
        
    def getProjInfo(self):
        return self.proj_info
        
    def loadTiff(self, tiffFile):
        """ Read dem file info via gdalinfo command."""
        
        # store file name
        self.fileName = os.path.basename(tiffFile.split('.tif')[0])
        
        # initialize daymetR package
        
        cmdInfo = ['gdalinfo', tiffFile]
        
        # Regular experssions for upper left coords extraction
        ulCoords = re.compile(r"""Upper\s+Left\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,\s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        
        # Regular experssions for lower right coords extraction
        lrCoords = re.compile(r"""Lower\s+Right\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,\s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        # Execute the command
        process = Popen(cmdInfo, stdout=PIPE, shell=False)
        output, err = process.communicate()
        
        if process.returncode != 0:
            raise RuntimeError("%r failed, status code %s stdout %r stderr %r" % (cmdInfo, process.returncode, output, err))
        
        # Process gdalinfo output by lines
        if isinstance(output, bytes):
            output = output.decode('utf-8')
        output = output.split('\n')
        lx = uly = rx = lry = 0
        for i in range(len(output) - 1, -1, -1):
            if output[i].startswith("Size is"):
                # Extract # of pixels along X,Y axis
                self.nPixelX = int(output[i].split(' ')[2][:-1])
                self.nPixelY = int(output[i].split(' ')[3])
                break
            if output[i].startswith("Upper Left"):
                temp = output[i].split('(')
                temp2 = output[i+3].split('(')
                lx = float(temp[1].split(',')[0].strip())
                uly = float(temp[1].split(',')[1].split(')')[0].strip())
                rx = float(temp2[1].split(',')[0].strip())
                lry = float(temp2[1].split(',')[1].split(')')[0].strip())
                bottom_right = str(rx) + "," + str(lry)
                top_left = str(lx) + "," + str(uly)
                self.projCoords.append((bottom_right,top_left))
            match = lrCoords.search(output[i])
            if match:
                lat = 0.0
                lon = 0.0
                # caculate lon & lat in decimal
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
                
                # upper left is three lines above
                match = ulCoords.search(output[i-3])
                lat = 0.0
                lon = 0.0
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
                
    def read_meta(self,dem):
        """
        Uses gdalinfo output to determine the projection zone and region of the original data.
        Then passes this information to convert_opentopo() to convert the data to Daymet's projection.
        """
        
        # Try opening the file and searching
        #proj_info = dict()
        
        # Add the filenames to the end of the list
        command = ['gdalinfo', dem]
        
        # Execute the gdalinfo command
        process = Popen(command, stdout=PIPE, shell=False)
        
        # Check for errors
        stdout, stderr = process.communicate()
        
        if process.returncode != 0:
            print(stderr)
            print('Failed to get original projection information from input data. Aborting')
            sys.exit(1)
        
        if isinstance(stdout, bytes):
            stdout = stdout.decode('utf-8')
        stdout = stdout.split('\n')
        
        for line in stdout:
            # Zone Information
            if line.startswith('PROJCS'):
                # Remove the punctation and break the individual words apart
                translator = str.maketrans('', '', ',[]"/')
                line = line.translate(translator)
                line = line.split()
                line = line[-1]
                # Remove the last character for North
                self.proj_info['zone'] = line[:-1]
                
                
            # Region Information
            elif line.startswith('    AUTHORITY'): 
                # Strip out the punctuation and split into space separated words
                line = ' '.join(re.split('[,"]', line))
                line = line.split()
                print(line[-2])
                self.proj_info['region'] = line[-2]
            elif line.startswith('        AUTHORITY'): 
                # Strip out the punctuation and split into space separated words
                line = ' '.join(re.split('[,"]', line))
                line = line.split()
                print(line[-2])
                self.proj_info['region'] = line[-2]
                
                
        # Convert the DEMs to Daymet's projection
        print('Converting DEM to Daymet\'s projection.')
        #convert_opentopo(proj_info)
        
        print('Finished warping OpenTopography.\n') 
        
    def convert_opentopo(self,proj_dir,tiff):
        """
        Creates another .tif file with the name .converted.tif for every .tif file located
        in the passed directory.The converted.tif file is supposed to be converted into the Daymet
        custom projection. Depends on theread_meta() method executing correctly. It doesn't check
        for the converted files before executing. Once the files are generated, script will call
        gdalinfo and try to parse the new coordinates from the output. The corner coordinates are
        returned in a list. Since everything is related to Daymet, it assumes the data is in the
        North and West hemispheres.
        """
        # Command string to convert the DEM files from Open Topography to DAYMET's projection
        
        #command = ['gdalwarp', '-s_srs', 'EPSG:' + self.proj_info['region'], '-overwrite', '-t_srs',"+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs",'-r', 'bilinear', '-of', 'GTiff', '-tr', '10', '-10']
        
        
        #Warp DEM to WGS84 Web Mercator Projection
        dem_file=tiff
        command = 'gdalwarp -overwrite -t_srs EPSG:3857 -r bilinear -of GTiff -dstnodata nan '
        dem_temp=proj_dir + "/" + "temp_warped.tif"
        command=command+ " " + dem_file
        command=command+ " " + dem_temp
        print(command)
        process = Popen(command, stdout=PIPE,shell=True)
        stdout,stderr = process.communicate()
        
        #Compress Output
        dem_output=proj_dir + "/" + self.getName() + "_converted.tif"
        command="gdal_translate -co compress=LZW " + dem_temp + " " + dem_output
        print(os.getcwd())
        print(command)
        process=Popen(command,stdout=PIPE,shell=True)
        stdout,stderr = process.communicate()
        
        #Remove the temporary warped file
        command= "rm " + dem_temp
        print(command)
        #process=Popen(command,stdout=PIPE,shell=True)
        #stdout,stderr = process.communicate()
        
        return dem_output
        
    def window_daymet(self):
        coords = self.projCoords
        ul = [str(math.floor(decimal.Decimal(coords[1][0]) / 1000) * 1000), str(math.ceil(decimal.Decimal(coords[1][1]) / 1000) * 1000)]
        lr = [str(math.ceil(decimal.Decimal(coords[0][0]) / 1000) * 1000), str(math.floor(decimal.Decimal(coords[0][1]) / 1000) * 1000)]
        command = ['gdal_translate', '-projwin', ul[0], ul[1], lr[0], lr[1], 'na_dem.tif', os.path.join(output, 'na_dem.part.tif')]
        print(command)