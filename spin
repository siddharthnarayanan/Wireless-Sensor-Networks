#include <m8c.h>        // part specific constants and macros  
#include "PSoCAPI.h"    // PSoC API definitions for all User Modules  
#include "psocgpioint.h"  

#define TRANSMITTER 1 

#define NODEid 1
 
#define SW1_PULLUP      0  
// Set this to 0 if SW1 uses a pulldown resistor.  
  
#define SW1_ENABLE_INT       {SW1_IntEn_ADDR |= SW1_MASK;}  
#define SW1_DISABLE_INT      {SW1_IntEn_ADDR &= ~SW1_MASK;}  
  

// LED blinking routines  
#define GREEN_LED_BLINK {GREEN_LED_On(); SoftDelay50msec(); SoftDelay50msec(); GREEN_LED_Off();}  
#define RED_LED_BLINK   {RED_LED_On(); SoftDelay50msec(); SoftDelay50msec(); RED_LED_Off();}  
  
// SW1 input logic  
#if (SW1_PULLUP)  
    #ifdef SW1_DataShadow  
        #define SET_SW1_FOR_INPUT    {SW1_DataShadow |= SW1_MASK; SW1_Data_ADDR = SW1_DataShadow;}     // Place SW1 pin in pulled up state  
    #else  
        #define SET_SW1_FOR_INPUT     {SW1_Data_ADDR |= SW1_MASK;}                                      // Place SW1 pin in pulled up state  
    #endif  
    #define SW1_ACTIVE               (~SW1_Data_ADDR & SW1_MASK)  
#else  
    #ifdef SW1_DataShadow  
        #define SET_SW1_FOR_INPUT    {SW1_DataShadow &= ~SW1_MASK; SW1_Data_ADDR = SW1_DataShadow;}    // Place SW1 pin in pulled down state  
    #else  
        #define SET_SW1_FOR_INPUT    {SW1_Data_ADDR &= ~SW1_MASK;}                                     // Place SW1 pin in pulled down state  
    #endif  
    #define SW1_ACTIVE               (SW1_Data_ADDR & SW1_MASK)  
#endif    // #if (SW1_PULLUP)  
  
  
  
 
  
  
// Application personality options  
#define TX  ((BOOL) 0)  
#define RX  ((BOOL) 1)  
  
											   
// Variables.  
BYTE AppBuf[16] = {                                     // Buffer for radio packet data  
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,  
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F                                                     
};  
BYTE AppBuf1[16] = {                                     // Buffer for radio packet data  
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,  
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F                                                     
};  
  
  
  
BOOL bPersonality;                                      // Indicator of whether the application runs as a transmitter or receiver  
BYTE RxLen;                                             // Length of a received packet  
XACT_CONFIG  XactState;                                 // Saved radio end state during low power operation  

BYTE adv[3] = { 0x04, 0x05, 0x06};


  
// Function prototypes  
void Init(void);  
void Receive(BYTE);  
void Transmit(BYTE, BYTE);   
BYTE ButtonPressed(void);  
void SoftDelay50msec(void);
void SendAdvt(void);
void RcvAdvt(void);
void Wait4Resp(void);
void SendResp(void);
void RcvData(void);
void SendData(void);
void RecvWithTimeout(BYTE freq);
void TransmitLong(BYTE freq, BYTE pkt);
void WaitForCTS(void);
void SendCTS(BYTE freq);

//--------------------------------------------------------------------------  
// MAIN  
//--------------------------------------------------------------------------  
void main(void)   
{  
    // Initialize the application  
    Init();  
      
    					// Check if SW1 is held during initial Power Up to determine   
    					// whether the application runs as a receiver or a transmitter.
	#ifdef TRANSMITTER					
   		SendAdvt();
		Wait4Resp();
		SendData();
	#else
		RcvAdvt();
		RcvData();
	#endif
}
	
	   
  
//-------------------------------------------------------------------  
// Called once at startup -   
//   Application Initialization Goes Here  
//-------------------------------------------------------------------  
void Init(void)  
{  
    // Visually indicate start of application to the user  
   // RED_LED_On();  
    //GREEN_LED_On();  
      
    if (!CYFISPI_Start()) {                 // Start the radio initialization and check for error.  
        // Handle failed initialization here.  
        GREEN_LED_Off();  
        while(1) {  
            RED_LED_BLINK;  
            SoftDelay50msec();  
        }  
    }      
  
    // Complete the radio initialization  
    CYFISPI_SetPtr((BYTE *)&AppBuf);        // Provide the radio data buffer parameters  
    CYFISPI_SetLength(sizeof(AppBuf));      // to the CYFISPI user module.  
    CYFISPI_ForceState(0);                  // Put the radio to sleep immediately.  
    CYFISPI_Write(0x0B,0x20);               // Disable the PMU.  
    CYFISPI_EnableInt();  
      
  
    SW1_DISABLE_INT;                              // Disable SW1's ability to generate an interrupt.  
    M8C_EnableIntMask(INT_MSK0, INT_MSK0_GPIO);	  // Enable the GPIO interrupt.  
    M8C_EnableGInt;                               // Enable interrupts.  
  
    // Indicate successful initialization.  
    //RED_LED_Off();  
    //GREEN_LED_Off();      
}  
  
//-------------------------------------------------------------------  
// Transmit() is the packet transmission handler.  
//-------------------------------------------------------------------  
void Transmit(BYTE freq, BYTE pkt) 
{
   	AppBuf[0] = pkt;      // Provide the radio data buffer parameters  
	CYFISPI_SetSopPnCode(0);  	//Pn CODE
	CYFISPI_SetChannel(0x10);  	//set the channel
	CYFISPI_SetFrequency(freq); //Setting the frequency
    CYFISPI_StartTransmit(15,1);                              // Initiate transmission.  
   
	while(1) {  
        
			if(CYFISPI_State & CYFISPI_COMPLETE) {             			 // Check for completion.  
           			 if(!(CYFISPI_State & CYFISPI_ERROR)) 
					 {             										 // Check for error.  
                 	//GREEN_LED_On();  									 //Handle successful packet transmission here  
            		 }   
                     else 
					 {  
                	//RED_LED_On();										 //Handle failed packet transmission here  
                     }
              break;    
             
        }  
    }  
    CYFISPI_EndTransmit();                                    // Complete the radio transaction.  
}  
 
//-------------------------------------------------------------------  
// Receive() is the packet reception handler.  
//-------------------------------------------------------------------  
void Receive(BYTE Freq)  
{      
	   // Provide the radio data buffer parameters  
	RED_LED_On();                                             // Indicate that the radio is listening.  
    CYFISPI_SetSopPnCode(0);  	//Pn CODE
	CYFISPI_SetChannel(0x10);  	//set the channel
	CYFISPI_SetFrequency(Freq); //Setting the frequency
    CYFISPI_StartReceive();                                   // Start listening for a packet.  
  
    while(1) {  
	
        if(CYFISPI_State & CYFISPI_COMPLETE) {                // Check to see if the radio stopped listening.  
            RxLen = CYFISPI_EndReceive();                     // Complete the radio transaction.  
              
            if(!(CYFISPI_State & CYFISPI_ERROR)) {            // Check for error.  
                // Handle a successful packet reception here  
                //GREEN_LED_BLINK; 
				SoftDelay50msec();
            }  
			
            break;          
        }
    }
                 
    //RED_LED_Off();                                             // Indicate that the radio is not listening.  
}

 
 
  
//-------------------------------------------------------------------  
// ButtonPressed() debounces the SW1 button input.  If the button is   
// not pressed, ButtonPressed() return FALSE.  If the the button is   
// pressed, ButtonPressed() waits for the button to be released and  
// returns TRUE.  
//-------------------------------------------------------------------  
BYTE ButtonPressed(void)  
{  
    										// Set up for input on SW1  
    SET_SW1_FOR_INPUT;  
	  										// Check to see if the input is active.  
    if(SW1_ACTIVE) {  
      									  // Wait 50 msec and sample a second time to debounce.  
        SoftDelay50msec();  
        if(SW1_ACTIVE) {  
            								// A debounced button press was detected.  Detect button release  
            								// by waiting until the first occurrence of the inactive state.  
            while(SW1_ACTIVE);   
            return TRUE;  
			
        }   
    }  
    return FALSE;  
}  
  
//-------------------------------------------------------------------  
// SoftDelay50msec provides a 50 ms Software Delay on a 12MHz CPU.  
//-------------------------------------------------------------------  
void SoftDelay50msec(void)  
{  
    unsigned int i;  
	  
    // Busy loop to delay approximately 50 ms on a 12 MHz CPU.  
    for(i = 0; i < 23100; i++) asm("NOP");  
}  

//--------------------------------------------------------------------
//Advertisement
//---------------------------------------------------------------------
void SendAdvt(void)
{
Transmit(0x20, adv[1]);
Transmit(0x30, adv[2]);

}

void RcvAdvt(void)
{
	Receive(0x10 * NODEid);
	if (AppBuf[0] == adv[NODEid -1])
		WaitForCTS();
}

void WaitForCTS(void)
{
	Receive(0x10 * NODEid);
	if(AppBuf[0] == 0xFF)
		SendResp();	
}
//-------------------------------------------------------------------
//Response
//------------------------------------------------------------------
BYTE resp[3] = { 0, 0, 0};
void Wait4Resp(void)
{
	//int i = 2;
	SendCTS(0x20);
	RecvWithTimeout(0x20);
	SendCTS(0x30);
	RecvWithTimeout(0x30);
}

void SendCTS(BYTE freq)
{
	Transmit(freq, 0xFF);
}

void RecvWithTimeout(BYTE freq)
{
	int i1 = 0;
	
	                                             // Indicate that the radio is listening.  
	//
    CYFISPI_SetSopPnCode(0);  	//Pn CODE
	CYFISPI_SetChannel(0x10);  	//set the channel
	CYFISPI_SetFrequency(freq); //Setting the frequency
	//CYFISPI_SetXactConfig(0x80);
		
	CYFISPI_StartReceive();                                   // Start listening for a packet.  

	while(1) 
	{   
		//i1++;
		if(CYFISPI_State & CYFISPI_COMPLETE) 
		{                // Check to see if the radio stopped listening.  
			                   // Complete the radio transaction.  
			RxLen = CYFISPI_EndReceive();  
			//GREEN_LED_On();
			//RED_LED_On();
			if(!(CYFISPI_State & CYFISPI_ERROR)) 
			{            // Check for error.  
				// Handle a successful packet reception here  
				resp[(int)(AppBuf[0] - 4)] = 1; 
				if (freq == 0x20)
				{
					GREEN_LED_On();
					//RED_LED_On();
					}
				else if (freq == 0x30)
					{	RED_LED_On();
//						GREEN_LED_On();
					}
			}  
		
        	break;          
		}
//		if(i1 > 30000)
//		{	RED_LED_Off();
//			GREEN_LED_Off();
//			if (freq == 0x20)
//			{
//				
//					RED_LED_On();
//					GREEN_LED_BLINK;
//				
//			}
//			else
//			{
//					
//					GREEN_LED_On();
//					RED_LED_BLINK;
//				
//			}
//			break;
//		}
	}
	
	
}


void SendResp(void)
{
	RED_LED_Off();
	GREEN_LED_On();
	TransmitLong(0x10 * NODEid, adv[NODEid - 1]);
	RED_LED_On();
	GREEN_LED_Off();
}

//-------------------------------------------------------------------  
// Transmit() is the packet transmission handler.  
//-------------------------------------------------------------------  
void TransmitLong(BYTE freq, BYTE pkt) 
{
   	AppBuf[0] = pkt;      // Provide the radio data buffer parameters  
	CYFISPI_SetSopPnCode(0);  	//Pn CODE
	CYFISPI_SetChannel(0x10);  	//set the channel
	CYFISPI_SetFrequency(freq); //Setting the frequency
    CYFISPI_StartTransmit(3,1);                              // Initiate transmission.  
   
	while(1) {  
        
			if(CYFISPI_State & CYFISPI_COMPLETE) {             			 // Check for completion.  
           			 if(!(CYFISPI_State & CYFISPI_ERROR)) 
					 {             										 // Check for error.  
                 	//GREEN_LED_On();  									 //Handle successful packet transmission here  
            		 }   
                     else 
					 {  
                	//RED_LED_On();										 //Handle failed packet transmission here  
                     }
              break;    
             
        }  
    }  
    CYFISPI_EndTransmit();                                    // Complete the radio transaction.  
} 

//----------------------------------------------------------------
//Data
//----------------------------------------------------------------
BYTE DATA[3] = { 0x11, 0x22, 0x33};
void SendData(void)
{	
	RED_LED_On();
	GREEN_LED_On();
	
	if(resp[NODEid] ==1)
	Transmit(0x10 * (NODEid+1) , DATA[NODEid]);
	else
	RED_LED_Off();
	
	if(resp[NODEid+1] == 1)
	Transmit(0x10 * (NODEid+2) , DATA[NODEid+1]);
	else
	GREEN_LED_Off();
	
}


void RcvData(void)
{
	Receive(0x10 * NODEid);
	if(AppBuf[0] == 0x11 * NODEid)
	{
	GREEN_LED_On();
	RED_LED_On();
	}
}
